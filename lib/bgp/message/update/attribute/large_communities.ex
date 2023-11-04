defmodule BGP.Message.UPDATE.Attribute.LargeCommunities do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.Message.OPEN

  @type large_community :: {OPEN.asn(), pos_integer(), pos_integer()}
  @type t :: %__MODULE__{large_communities: [large_community()]}
  defstruct large_communities: []

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(<<data::binary>>, session),
    do: {%__MODULE__{large_communities: decode_large_communities(data, [])}, session}

  defp decode_large_communities(<<>>, large_communities), do: Enum.reverse(large_communities)

  defp decode_large_communities(
         <<asn::32, data1::32, data2::32, rest::binary>>,
         large_communities
       ),
       do: decode_large_communities(rest, [{asn, data1, data2} | large_communities])

  @impl Encoder
  def encode(%__MODULE__{large_communities: large_communities}, session) do
    {data, length} =
      Enum.map_reduce(large_communities, 0, fn {asn, data1, data2}, length ->
        {[<<asn::32>>, <<data1::32>>, <<data2::32>>], length + 12}
      end)

    {data, length, session}
  end
end
