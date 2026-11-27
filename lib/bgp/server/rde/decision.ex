defmodule BGP.Server.RDE.Decision do
  @moduledoc """
  BGP Route Selection

  Implements route feasibility checks and route selection, as described in
  [RFC4271 Section 9.1.2](https://datatracker.ietf.org/doc/html/rfc4271#section-9.1.2).

  Selection works by successively eliminating candidates, as the RFC describes,
  instead of pairwise comparisons: MED is only comparable between routes from the
  same neighbor AS, which makes pairwise comparison non-transitive and the result
  dependent on the order routes are compared in.
  """

  alias BGP.Message.OPEN
  alias BGP.Server.RDE.Route

  @doc """
  Returns true if `route` can be considered for selection by a speaker with `local_asn`.

  A route is not feasible if it has no NEXT_HOP or if `local_asn` is in its AS_PATH.
  """
  @spec feasible?(Route.t(), OPEN.asn()) :: boolean()
  def feasible?(%Route{next_hop: nil}, _local_asn), do: false
  def feasible?(%Route{} = route, local_asn), do: not Route.as_path_contains?(route, local_asn)

  @doc """
  Selects the best route among `routes` for the same prefix.

  Routes are expected to be feasible, see `feasible?/2`.
  """
  @spec select([Route.t()]) :: Route.t() | nil
  def select([]), do: nil

  def select(routes) do
    routes
    # 9.1.2: highest Degree of Preference
    |> keep_max_by(& &1.preference)
    # 9.1.2.2 (a): lowest number of AS numbers in AS_PATH
    |> keep_min_by(& &1.as_path_length)
    # 9.1.2.2 (b): lowest ORIGIN
    |> keep_min_by(& &1.origin)
    # 9.1.2.2 (c): lowest MED among routes from the same neighbor AS
    |> lowest_med()
    # 9.1.2.2 (d): prefer routes learned via eBGP
    |> prefer_ebgp()
    # 9.1.2.2 (e): lowest interior cost to NEXT_HOP, skipped as no IGP is available
    # 9.1.2.2 (f): lowest BGP Identifier
    |> keep_min_by(&IP.Address.to_integer(&1.peer_bgp_id))
    # 9.1.2.2 (g): lowest peer address
    |> keep_min_by(&IP.Address.to_integer(&1.peer))
    |> hd()
  end

  defp lowest_med(routes) do
    routes
    |> Enum.group_by(& &1.neighbor_as)
    |> Enum.flat_map(fn {_neighbor_as, routes} -> keep_min_by(routes, & &1.med) end)
  end

  defp prefer_ebgp(routes) do
    case Enum.reject(routes, & &1.ibgp) do
      [] -> routes
      ebgp_routes -> ebgp_routes
    end
  end

  defp keep_min_by(routes, fun) do
    min = routes |> Enum.map(fun) |> Enum.min()
    Enum.filter(routes, &(fun.(&1) == min))
  end

  defp keep_max_by(routes, fun) do
    max = routes |> Enum.map(fun) |> Enum.max()
    Enum.filter(routes, &(fun.(&1) == max))
  end
end
