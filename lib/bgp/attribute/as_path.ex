defmodule BGP.Attribute.ASPath do
  @type type :: :as_set | :as_sequence
  @type length :: non_neg_integer()
  @type t :: %__MODULE__{type: type(), length: length()}

  @enforce_keys [:type, :length]
  defstruct length: nil, type: nil, value: []

  alias BGP.Attribute

  @behaviour Attribute

  @impl Attribute
  def decode(<<type::8, length::8, data::binary-size(length)>>),
    do: {:ok, %__MODULE__{type: decode_type(type), length: length, value: decode_value([], data)}}

  def decode(<<_type::8>>), do: :error

  defp decode_type(1), do: :as_set
  defp decode_type(2), do: :as_sequence

  defp decode_value(asns, <<>>), do: Enum.reverse(asns)
  defp decode_value(asns, <<asn::16, rest::binary>>), do: decode_value([asn | asns], rest)

  @impl Attribute
  def encode(%__MODULE__{type: type, length: length, value: value}),
    do: [<<encode_type(type)::8, length::8>>, Enum.map(value, &<<&1::16>>)]

  defp encode_type(:as_set), do: 1
  defp encode_type(:as_sequence), do: 2
end
