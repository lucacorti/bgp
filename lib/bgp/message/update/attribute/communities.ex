defmodule BGP.Message.Update.Attribute.Communities do
  @moduledoc false

  @type community ::
          :graceful_shutdown
          | :accept_own
          | :route_filter_translated_v4
          | :route_filter_v4
          | :route_filter_translated_v6
          | :route_filter_v6
          | :llgr_stale
          | :no_llgr
          | :accept_own_nexthop
          | :standby_pe
          | :blackhole
          | :no_export
          | :no_advertise
          | :no_export_subconfed
          | :no_peer
  @type t :: %__MODULE__{communities: [community()]}
  defstruct communities: []

  alias BGP.Message.Encoder

  @behaviour Encoder

  @communities [
    {0xFFFF0000, :graceful_shutdown},
    {0xFFFF0001, :accept_own},
    {0xFFFF0002, :route_filter_translated_v4},
    {0xFFFF0003, :route_filter_v4},
    {0xFFFF0004, :route_filter_translated_v6},
    {0xFFFF0005, :route_filter_v6},
    {0xFFFF0006, :llgr_stale},
    {0xFFFF0007, :no_llgr},
    {0xFFFF0008, :accept_own_nexthop},
    {0xFFFF0009, :standby_pe},
    {0xFFFF029A, :blackhole},
    {0xFFFFFF01, :no_export},
    {0xFFFFFF02, :no_advertise},
    {0xFFFFFF03, :no_export_subconfed},
    {0xFFFFFF04, :no_peer}
  ]

  @impl Encoder
  def decode(<<communities::binary>>, _options),
    do: {:ok, %__MODULE__{communities: decode_communities(communities, [])}}

  defp decode_communities(<<>>, communities), do: Enum.reverse(communities)

  defp decode_communities(<<community::32, rest::binary>>, communities),
    do: decode_communities(rest, [decode_community(community) | communities])

  for {code, community} <- @communities do
    defp decode_community(unquote(code)), do: unquote(community)
  end

  @impl Encoder
  def encode(%__MODULE__{communities: communities}, _options),
    do: Enum.map(communities, &encode_community(&1))

  for {code, community} <- @communities do
    defp encode_community(unquote(community)), do: unquote(code)
  end
end
