defmodule BGP.Server.RDE.Route do
  @moduledoc """
  BGP Route

  A route as stored in RIBs, with the information needed by the Decision Process
  extracted from path attributes when the route is received.
  """

  alias BGP.Message.{OPEN, UPDATE.Attribute}
  alias BGP.Message.UPDATE.Attribute.{ASPath, LocalPref, MultiExitDisc, NextHop, Origin}
  alias BGP.Server.Session

  @origin_incomplete 2

  @type preference :: non_neg_integer()

  @type t :: %__MODULE__{
          prefix: IP.Prefix.t(),
          peer: IP.Address.t(),
          peer_bgp_id: OPEN.bgp_id(),
          ibgp: boolean(),
          preference: preference(),
          as_path: ASPath.t() | nil,
          as_path_length: non_neg_integer(),
          neighbor_as: OPEN.asn() | nil,
          origin: non_neg_integer(),
          local_pref: non_neg_integer() | nil,
          med: non_neg_integer(),
          next_hop: IP.Address.t() | nil,
          path_attributes: [Attribute.t()]
        }

  @enforce_keys [:prefix, :peer, :peer_bgp_id, :ibgp, :path_attributes]
  defstruct prefix: nil,
            peer: nil,
            peer_bgp_id: nil,
            ibgp: false,
            preference: 0,
            as_path: nil,
            as_path_length: 0,
            neighbor_as: nil,
            origin: @origin_incomplete,
            local_pref: nil,
            med: 0,
            next_hop: nil,
            path_attributes: []

  @doc """
  Builds a route for `prefix` received from `session` with `path_attributes`.

  `preference` (Degree of Preference) defaults to 0, it is set by Phase 1 of the
  Decision Process.
  """
  @spec new(Session.data(), IP.Prefix.t(), [Attribute.t()]) :: t()
  def new(%Session{} = session, prefix, path_attributes) do
    Enum.reduce(
      path_attributes,
      %__MODULE__{
        prefix: prefix,
        peer: session.host,
        peer_bgp_id: session.peer_bgp_id,
        ibgp: session.ibgp,
        path_attributes: path_attributes
      },
      &put_attribute/2
    )
  end

  defp put_attribute(%Attribute{value: %ASPath{} = as_path}, route) do
    %{
      route
      | as_path: as_path,
        as_path_length: as_path_length(as_path),
        neighbor_as: neighbor_as(as_path)
    }
  end

  defp put_attribute(%Attribute{value: %LocalPref{value: value}}, route),
    do: %{route | local_pref: value}

  defp put_attribute(%Attribute{value: %MultiExitDisc{value: value}}, route),
    do: %{route | med: value}

  defp put_attribute(%Attribute{value: %NextHop{value: value}}, route),
    do: %{route | next_hop: value}

  defp put_attribute(%Attribute{value: %Origin{value: value}}, route),
    do: %{route | origin: value}

  defp put_attribute(_attribute, route), do: route

  # RFC 4271 9.1.2.2 (a): an AS_SET counts as 1 regardless of the number of ASes in it.
  # RFC 5065 5.3: confederation segments are not counted.
  defp as_path_length(%ASPath{value: segments}) do
    Enum.reduce(segments, 0, fn
      {:as_sequence, _length, asns}, length -> length + length(asns)
      {:as_set, _length, _asns}, length -> length + 1
      {_confed_type, _length, _asns}, length -> length
    end)
  end

  # RFC 4271 9.1.2.2 (c): the neighbor AS is the leftmost AS in the AS_PATH.
  # Leading confederation segments are skipped (RFC 5065 5.3).
  defp neighbor_as(%ASPath{value: segments}) do
    segments
    |> Enum.drop_while(fn {type, _length, _asns} ->
      type in [:as_confed_sequence, :as_confed_set]
    end)
    |> case do
      [{:as_sequence, _length, [asn | _asns]} | _segments] -> asn
      _segments -> nil
    end
  end

  @doc """
  Returns true if `asn` appears anywhere in the route AS_PATH.
  """
  @spec as_path_contains?(t(), OPEN.asn()) :: boolean()
  def as_path_contains?(%__MODULE__{as_path: nil}, _asn), do: false

  def as_path_contains?(%__MODULE__{as_path: %ASPath{value: segments}}, asn),
    do: Enum.any?(segments, fn {_type, _length, asns} -> asn in asns end)
end
