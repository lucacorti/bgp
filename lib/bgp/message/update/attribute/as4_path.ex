defmodule BGP.Message.UPDATE.Attribute.AS4Path do
  @moduledoc false

  alias BGP.Message.{Encoder, NOTIFICATION}

  @type type :: :as_set | :as_sequence
  @type length :: non_neg_integer()
  @type t :: %__MODULE__{type: type(), length: length()}

  @enforce_keys [:type, :length]
  defstruct length: nil, type: nil, value: []

  @behaviour Encoder

  @impl Encoder
  def decode(<<type::8, length::8, asns::binary>>, _fsm),
    do: %__MODULE__{type: decode_type(type), length: length, value: decode_asns([], asns)}

  defp decode_type(1), do: :as_set
  defp decode_type(2), do: :as_sequence

  defp decode_type(_data) do
    raise NOTIFICATION, code: :update_message
  end

  defp decode_asns(asns, <<>>), do: Enum.reverse(asns)
  defp decode_asns(asns, <<asn::32, rest::binary>>), do: decode_asns([asn | asns], rest)

  defp decode_asns(_asns, _data) do
    raise NOTIFICATION, code: :update_message
  end

  @impl Encoder
  def encode(%__MODULE__{type: type, length: length, value: value}, _fsm) do
    {path, path_length} =
      Enum.map_reduce(value, 0, fn asn, length ->
        {<<asn::32>>, length + 4}
      end)

    {[<<encode_type(type)::8>>, <<length::8>>, path], 2 + path_length}
  end

  defp encode_type(:as_set), do: 1
  defp encode_type(:as_sequence), do: 2

  defp encode_type(_data) do
    raise NOTIFICATION, code: :update_message
  end
end
