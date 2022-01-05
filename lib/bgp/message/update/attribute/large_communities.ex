defmodule BGP.Message.UPDATE.Attribute.LargeCommunities do
  @moduledoc false

  @type large_community :: {BGP.asn(), pos_integer(), pos_integer()}
  @type t :: %__MODULE__{large_communities: [large_community()]}
  defstruct large_communities: []

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(<<large_communities::binary>>, _options),
    do: {:ok, %__MODULE__{large_communities: decode_large_communities(large_communities, [])}}

  defp decode_large_communities(<<>>, large_communities), do: Enum.reverse(large_communities)

  defp decode_large_communities(
         <<asn::32, data1::32, data2::32, rest::binary>>,
         large_communities
       ),
       do: decode_large_communities(rest, [{asn, data1, data2} | large_communities])

  @impl Encoder
  def encode(%__MODULE__{large_communities: large_communities}, _options),
    do: Enum.map(large_communities, &encode_large_community(&1))

  defp encode_large_community({asn, data1, data2}), do: <<asn::32, data1::32, data2::32>>
end
