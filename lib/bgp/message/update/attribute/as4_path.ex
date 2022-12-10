defmodule BGP.Message.UPDATE.Attribute.AS4Path do
  @moduledoc false

  alias BGP.Message.{Encoder, NOTIFICATION}

  @type type :: :as_set | :as_sequence
  @type length :: non_neg_integer()
  @type t :: %__MODULE__{value: [{type(), length(), BGP.asn()}]}

  defstruct value: []

  @behaviour Encoder

  @impl Encoder
  def decode(data, _fsm) do
    %__MODULE__{value: decode_path(data, [])}
  end

  defp decode_path(<<>>, path), do: Enum.reverse(path)

  defp decode_path(<<type::8, length::8, data::binary>>, path) do
    asns_length = length * 4
    <<asns::binary-size(asns_length), rest::binary>> = data
    decode_path(rest, [{decode_type(type), length, decode_asns(asns, [])} | path])
  end

  defp decode_path(data, _path) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_as_path, data: data
  end

  defp decode_type(1), do: :as_set
  defp decode_type(2), do: :as_sequence

  defp decode_asns(<<>>, asns), do: Enum.reverse(asns)

  defp decode_asns(<<asn::16, rest::binary>>, asns),
    do: decode_asns(rest, [asn | asns])

  @impl Encoder
  def encode(%__MODULE__{value: value}, _fsm) do
    Enum.map_reduce(value, 0, fn {type, length, asns}, path_length ->
      {
        [
          <<encode_type(type)::8>>,
          <<length::8>>,
          Enum.map(asns, &<<&1::size(32)>>)
        ],
        path_length + 2 + length * 4
      }
    end)
  end

  defp encode_type(:as_set), do: 1
  defp encode_type(:as_sequence), do: 2
end
