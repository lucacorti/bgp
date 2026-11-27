defmodule BGP.Server.RDE.DecisionTest do
  use ExUnit.Case, async: true

  alias BGP.Message.UPDATE.Attribute
  alias BGP.Message.UPDATE.Attribute.{ASPath, LocalPref, MultiExitDisc, NextHop, Origin}
  alias BGP.Server.RDE.{Decision, Route}
  alias BGP.Server.Session
  alias BGP.Server.Session.Transport.TCP

  import IP.Sigil

  @local_asn 65_000

  describe "Route.new/3" do
    test "extracts attributes" do
      route =
        route(
          as_path: [{:as_sequence, 2, [65_001, 65_002]}],
          origin: 1,
          med: 50,
          local_pref: 200
        )

      assert route.prefix == ~i(192.0.2.0/24)
      assert route.peer == ~i(10.0.0.1)
      assert route.peer_bgp_id == ~i(1.1.1.1)
      assert route.next_hop == ~i(10.0.0.1)
      assert route.as_path_length == 2
      assert route.neighbor_as == 65_001
      assert route.origin == 1
      assert route.med == 50
      assert route.local_pref == 200
    end

    test "counts AS_SET as 1 and ignores confederation segments in AS_PATH length" do
      route =
        route(
          as_path: [
            {:as_confed_sequence, 2, [64_512, 64_513]},
            {:as_sequence, 2, [65_001, 65_002]},
            {:as_set, 3, [65_003, 65_004, 65_005]}
          ]
        )

      assert route.as_path_length == 3
      assert route.neighbor_as == 65_001
    end

    test "has no neighbor AS when the AS_PATH starts with an AS_SET" do
      route = route(as_path: [{:as_set, 1, [65_003]}, {:as_sequence, 1, [65_001]}])
      assert is_nil(route.neighbor_as)
    end

    test "defaults missing MED to 0 and missing LOCAL_PREF to nil" do
      route = route([])
      assert route.med == 0
      assert is_nil(route.local_pref)
    end
  end

  describe "feasible?/2" do
    test "accepts routes with a NEXT_HOP and no loops" do
      assert Decision.feasible?(route([]), @local_asn)
    end

    test "rejects routes without NEXT_HOP" do
      refute Decision.feasible?(route(next_hop: nil), @local_asn)
    end

    test "rejects routes with the local AS in the AS_PATH" do
      route = route(as_path: [{:as_sequence, 2, [65_001, @local_asn]}])
      refute Decision.feasible?(route, @local_asn)

      route = route(as_path: [{:as_set, 2, [65_002, @local_asn]}])
      refute Decision.feasible?(route, @local_asn)
    end
  end

  describe "select/1" do
    test "returns nil without routes" do
      assert is_nil(Decision.select([]))
    end

    test "prefers higher degree of preference regardless of tie breaking" do
      preferred = route(preference: 200, as_path: [{:as_sequence, 3, [1, 2, 3]}])
      other = route(preference: 100, as_path: [{:as_sequence, 1, [1]}], peer: ~i(10.0.0.2))

      assert_selected(preferred, [preferred, other])
    end

    test "prefers shorter AS_PATH" do
      preferred = route(as_path: [{:as_sequence, 1, [1]}], peer: ~i(10.0.0.2))
      other = route(as_path: [{:as_sequence, 2, [1, 2]}])

      assert_selected(preferred, [preferred, other])
    end

    test "prefers lower ORIGIN" do
      preferred = route(origin: 0, peer: ~i(10.0.0.2))
      other = route(origin: 2)

      assert_selected(preferred, [preferred, other])
    end

    test "prefers lower MED from the same neighbor AS" do
      preferred = route(med: 10, peer: ~i(10.0.0.2), bgp_id: ~i(2.2.2.2))
      other = route(med: 20)

      assert_selected(preferred, [preferred, other])
    end

    test "treats missing MED as the lowest value" do
      preferred = route(peer: ~i(10.0.0.2), bgp_id: ~i(2.2.2.2))
      other = route(med: 1)

      assert_selected(preferred, [preferred, other])
    end

    test "does not compare MED between different neighbor ASes" do
      preferred = route(med: 100, as_path: [{:as_sequence, 1, [65_001]}])

      other =
        route(
          med: 10,
          as_path: [{:as_sequence, 1, [65_002]}],
          peer: ~i(10.0.0.2),
          bgp_id: ~i(2.2.2.2)
        )

      assert_selected(preferred, [preferred, other])
    end

    test "selection does not depend on route order when MED is not comparable" do
      # Pairwise comparison could pick any of these depending on order.
      a = route(med: 10, peer: ~i(10.0.0.3), bgp_id: ~i(3.3.3.3))
      b = route(med: 20, peer: ~i(10.0.0.1), bgp_id: ~i(1.1.1.1))

      c =
        route(
          med: 5,
          as_path: [{:as_sequence, 1, [65_002]}],
          peer: ~i(10.0.0.2),
          bgp_id: ~i(2.2.2.2)
        )

      assert_selected(c, [a, b, c])
    end

    test "prefers eBGP over iBGP" do
      preferred = route(ibgp: false, peer: ~i(10.0.0.2), bgp_id: ~i(2.2.2.2))
      other = route(ibgp: true)

      assert_selected(preferred, [preferred, other])
    end

    test "prefers lowest BGP Identifier" do
      preferred = route(bgp_id: ~i(1.1.1.1), peer: ~i(10.0.0.2))
      other = route(bgp_id: ~i(2.2.2.2), peer: ~i(10.0.0.1))

      assert_selected(preferred, [preferred, other])
    end

    test "prefers lowest peer address with the same BGP Identifier" do
      preferred = route(peer: ~i(10.0.0.1))
      other = route(peer: ~i(10.0.0.2))

      assert_selected(preferred, [preferred, other])
    end
  end

  defp assert_selected(expected, routes) do
    for permutation <- permutations(routes) do
      assert Decision.select(permutation) == expected
    end
  end

  defp permutations([]), do: [[]]

  defp permutations(list),
    do: for(elem <- list, rest <- permutations(list -- [elem]), do: [elem | rest])

  defp route(opts) do
    peer = Keyword.get(opts, :peer, ~i(10.0.0.1))

    session = %Session{
      asn: @local_asn,
      bgp_id: ~i(9.9.9.9),
      host: peer,
      ibgp: Keyword.get(opts, :ibgp, false),
      mode: :passive,
      notification_without_open: false,
      peer_bgp_id: Keyword.get(opts, :bgp_id, ~i(1.1.1.1)),
      port: 179,
      server: nil,
      start: :manual,
      transport: TCP,
      transport_opts: []
    }

    attributes =
      [
        %Origin{value: Keyword.get(opts, :origin, 0)},
        %ASPath{value: Keyword.get(opts, :as_path, [{:as_sequence, 1, [65_001]}])},
        Keyword.get(opts, :next_hop, peer) && %NextHop{value: Keyword.get(opts, :next_hop, peer)},
        opts[:med] && %MultiExitDisc{value: opts[:med]},
        opts[:local_pref] && %LocalPref{value: opts[:local_pref]}
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&%Attribute{transitive: 1, value: &1})

    session
    |> Route.new(~i(192.0.2.0/24), attributes)
    |> Map.put(:preference, Keyword.get(opts, :preference, 0))
  end
end
