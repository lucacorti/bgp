defmodule BGP.Server.RDETest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias BGP.Message.UPDATE
  alias BGP.Message.UPDATE.Attribute
  alias BGP.Message.UPDATE.Attribute.{ASPath, NextHop, Origin}
  alias BGP.Server
  alias BGP.Server.RDE
  alias BGP.Server.RDE.RIB
  alias BGP.Server.Session
  alias BGP.Server.Session.Transport.TCP

  import IP.Sigil

  @server BGP.RDETestServer
  @local_asn 65_000

  # Long enough for the Decision Process not to run during tests inspecting the queue.
  @default_interval 60_000

  setup ctx do
    start_supervised!({Registry, keys: :unique, name: Server.session_registry(@server)})

    start_supervised!(
      {RDE, server: @server, asn: @local_asn, interval: ctx[:interval] || @default_interval}
    )

    %{session: session(~i(10.0.0.1), ~i(1.1.1.1))}
  end

  describe "queue" do
    test "queues peer down when the session process exits", %{session: session} do
      update = %UPDATE{nlri: [~i(192.0.2.0/24)]}

      {pid, ref} = spawn_monitor(fn -> RDE.queue_update(@server, session, update) end)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

      assert %RDE{monitors: monitors} = data = await_queue_length(2)
      assert monitors == %{}

      assert [{:update, session, update}, {:peer_down, session.host}] ==
               :queue.to_list(data.update_queue)
    end

    test "monitors each session process once", %{session: session} do
      peer = start_peer(session)

      withdraw(peer, ~i(192.0.2.0/24))
      withdraw(peer, ~i(192.0.2.0/24))

      assert %RDE{monitors: monitors} = await_queue_length(2)
      assert monitors == %{peer => session.host}
    end

    test "queues explicit peer down", %{session: session} do
      :ok = RDE.peer_down(@server, session.host)

      assert %RDE{} = data = await_queue_length(1)
      assert [{:peer_down, session.host}] == :queue.to_list(data.update_queue)
    end
  end

  describe "decision process" do
    @describetag interval: 20

    @prefix ~i(192.0.2.0/24)

    test "selects the best route and falls back when it is withdrawn", %{session: session_a} do
      session_b = session(~i(10.0.0.2), ~i(2.2.2.2))
      peer_a = start_peer(session_a)
      peer_b = start_peer(session_b)

      announce(peer_a, @prefix, [65_001])
      announce(peer_b, @prefix, [65_002, 65_003])
      await_best_peer(@prefix, session_a.host)

      withdraw(peer_a, @prefix)
      await_best_peer(@prefix, session_b.host)

      withdraw(peer_b, @prefix)
      await_best_peer(@prefix, nil)
    end

    test "withdraws routes on explicit peer down", %{session: session} do
      peer = start_peer(session)

      announce(peer, @prefix, [65_001])
      await_best_peer(@prefix, session.host)

      :ok = RDE.peer_down(@server, session.host)
      await_best_peer(@prefix, nil)
    end

    test "withdraws routes when the session process exits", %{session: session_a} do
      session_b = session(~i(10.0.0.2), ~i(2.2.2.2))
      peer_a = start_peer(session_a)
      peer_b = start_peer(session_b)

      announce(peer_a, @prefix, [65_001])
      announce(peer_b, @prefix, [65_002, 65_003])
      await_best_peer(@prefix, session_a.host)

      stop_peer(peer_a)
      await_best_peer(@prefix, session_b.host)
    end

    test "ignores routes with the local AS in the AS_PATH", %{session: session} do
      peer = start_peer(session)
      other_prefix = ~i(198.51.100.0/24)

      announce(peer, @prefix, [65_001, @local_asn])
      announce(peer, other_prefix, [65_001])

      await_best_peer(other_prefix, session.host)
      assert is_nil(loc_rib(@prefix))
    end
  end

  defp session(host, peer_bgp_id) do
    %Session{
      asn: @local_asn,
      bgp_id: ~i(9.9.9.9),
      host: host,
      mode: :passive,
      notification_without_open: false,
      peer_bgp_id: peer_bgp_id,
      port: 179,
      server: @server,
      start: :manual,
      transport: TCP,
      transport_opts: []
    }
  end

  # Simulates a session process, the RDE monitors the process queueing UPDATEs.
  defp start_peer(session) do
    test = self()

    pid =
      spawn(fn ->
        peer_loop(session, test)
      end)

    on_exit(fn -> Process.exit(pid, :kill) end)
    pid
  end

  defp peer_loop(session, test) do
    receive do
      {:update, update} ->
        :ok = RDE.queue_update(@server, session, update)
        send(test, {:queued, self()})
        peer_loop(session, test)

      :stop ->
        :ok
    end
  end

  defp stop_peer(pid) do
    ref = Process.monitor(pid)
    send(pid, :stop)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
  end

  defp announce(peer, prefix, as_path) do
    send_update(peer, %UPDATE{
      nlri: [prefix],
      path_attributes: [
        %Attribute{transitive: 1, value: %Origin{value: 0}},
        %Attribute{transitive: 1, value: %ASPath{value: [{:as_sequence, 1, as_path}]}},
        %Attribute{transitive: 1, value: %NextHop{value: ~i(10.0.0.254)}}
      ]
    })
  end

  defp withdraw(peer, prefix), do: send_update(peer, %UPDATE{withdrawn_routes: [prefix]})

  defp send_update(peer, update) do
    send(peer, {:update, update})
    assert_receive {:queued, ^peer}
  end

  defp loc_rib(prefix) do
    {_state, %RDE{loc_rib: loc_rib}} = :sys.get_state(Server.rde_for(@server))

    Enum.find_value(RIB.dump(loc_rib), fn
      {^prefix, route} -> route
      _entry -> nil
    end)
  end

  # Waits for the Loc-RIB route for `prefix` to be from `peer`, nil means no route.
  defp await_best_peer(prefix, peer, attempts \\ 50) do
    route = loc_rib(prefix)

    cond do
      peer == (route && route.peer) ->
        route

      attempts > 0 ->
        Process.sleep(10)
        await_best_peer(prefix, peer, attempts - 1)

      true ->
        flunk("expected Loc-RIB route for #{prefix} from #{inspect(peer)}: #{inspect(route)}")
    end
  end

  defp await_queue_length(length, attempts \\ 50) do
    {:idle, %RDE{} = data} = :sys.get_state(Server.rde_for(@server))

    cond do
      :queue.len(data.update_queue) == length -> data
      attempts > 0 -> Process.sleep(10) && await_queue_length(length, attempts - 1)
      true -> flunk("expected #{length} queued events, got: #{inspect(data.update_queue)}")
    end
  end
end
