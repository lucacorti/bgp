defmodule BGP.Message.UPDATE.Attribute.ASPath do
  @moduledoc false

  alias BGP.Message.{Encoder, NOTIFICATION}

  @type type :: :as_set | :as_sequence
  @type length :: non_neg_integer()
  @type t :: %__MODULE__{type: type(), length: length()}

  @enforce_keys [:type, :length]
  defstruct length: nil, type: nil, value: []

  @behaviour Encoder

  @impl Encoder
  def decode(<<type::8, length::8, asns::binary>>, options) do
    four_octets = Keyword.get(options, :four_octets, false)

    %__MODULE__{
      type: decode_type(type),
      length: length,
      value: decode_asns(asns, four_octets, [])
    }
  end

  defp decode_type(1), do: :as_set
  defp decode_type(2), do: :as_sequence

  defp decode_asns(<<>>, _four_octets, asns), do: Enum.reverse(asns)

  defp decode_asns(<<asn::32, rest::binary>>, true = four_octets, asns),
    do: decode_asns(rest, four_octets, [asn | asns])

  defp decode_asns(<<asn::16, rest::binary>>, false = four_octets, asns),
    do: decode_asns(rest, four_octets, [asn | asns])

  defp decode_asns(_data, _four_octets, _asns) do
    raise NOTIFICATION, code: :update_message
  end

  @impl Encoder
  def encode(%__MODULE__{type: type, length: length, value: value}, options) do
    as_length =
      Enum.find_value(options, 16, fn
        {:four_octets, true} -> 32
        _ -> nil
      end)

    [<<encode_type(type)::8, length::8>>, Enum.map(value, &<<&1::integer-size(as_length)>>)]
  end

  defp encode_type(:as_set), do: 1
  defp encode_type(:as_sequence), do: 2

  defp encode_type(_type) do
    raise NOTIFICATION, code: :update_message
  end
end
