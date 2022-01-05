defmodule BGP.Message.Update.Attribute.AS4Path do
  @moduledoc false

  @type type :: :as_set | :as_sequence
  @type length :: non_neg_integer()
  @type t :: %__MODULE__{type: type(), length: length()}

  @enforce_keys [:type, :length]
  defstruct length: nil, type: nil, value: []

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(<<type::8, length::8, asns::binary>>, _options) do
    {:ok, %__MODULE__{type: decode_type(type), length: length, value: decode_asns([], asns)}}
  end

  defp decode_type(1), do: :as_set
  defp decode_type(2), do: :as_sequence

  defp decode_asns(asns, <<>>), do: Enum.reverse(asns)
  defp decode_asns(asns, <<asn::32, rest::binary>>), do: decode_asns([asn | asns], rest)

  @impl Encoder
  def encode(%__MODULE__{type: type, length: length, value: value}, _options),
    do: [<<encode_type(type)::8, length::8>>, Enum.map(value, &<<&1::32>>)]

  defp encode_type(:as_set), do: 1
  defp encode_type(:as_sequence), do: 2
end
