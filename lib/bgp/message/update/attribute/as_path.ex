defmodule BGP.Message.UPDATE.Attribute.ASPath do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.FSM
  alias BGP.Message.{Encoder, NOTIFICATION}

  @type type :: :as_sequence | :as_set | :as_confed_sequence | :as_confed_set
  @type length :: non_neg_integer()
  @type t :: %__MODULE__{value: [{type(), length(), BGP.asn()}]}

  defstruct value: []

  @as_trans 23_456
  @asn_2octets_max 65_535

  @behaviour Encoder

  @impl Encoder
  def decode(data, fsm) do
    {%__MODULE__{value: decode_path(data, fsm, [])}, fsm}
  end

  defp decode_path(<<>>, _fsm, path), do: Enum.reverse(path)

  defp decode_path(<<type::8, length::8, data::binary>>, %FSM{four_octets: true} = fsm, path) do
    asn_size = length * 4
    <<asns::binary-size(asn_size), rest::binary>> = data
    decode_path(rest, fsm, [{decode_type(type), length, decode_asns(asns, [], fsm)} | path])
  end

  defp decode_path(<<type::8, length::8, data::binary>>, fsm, path) do
    asn_size = length * 2
    <<asns::binary-size(asn_size), rest::binary>> = data
    decode_path(rest, fsm, [{decode_type(type), length, decode_asns(asns, [], fsm)} | path])
  end

  defp decode_path(data, _fsm, _path) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_as_path, data: data
  end

  defp decode_type(1), do: :as_set
  defp decode_type(2), do: :as_sequence
  defp decode_type(3), do: :as_confed_sequence
  defp decode_type(4), do: :as_confed_set

  defp decode_asns(<<>>, asns, _fsm), do: Enum.reverse(asns)

  defp decode_asns(<<asn::32, rest::binary>>, asns, %FSM{four_octets: true} = fsm),
    do: decode_asns(rest, [asn | asns], fsm)

  defp decode_asns(<<asn::16, rest::binary>>, asns, fsm),
    do: decode_asns(rest, [asn | asns], fsm)

  @impl Encoder
  def encode(%__MODULE__{value: value}, %FSM{} = fsm) do
    {data, length} = encode_path(value, fsm)
    {data, length, fsm}
  end

  defp encode_path(path, fsm) do
    Enum.map_reduce(path, 0, fn {type, length, asns}, path_length ->
      {asns, asns_length} = encode_asns(asns, fsm)
      {[<<encode_type(type)::8>>, <<length::8>> | asns], path_length + 2 + asns_length}
    end)
  end

  defp encode_asns(asns, fsm) do
    Enum.map_reduce(asns, 0, fn asn, length ->
      {asn, size} = encode_asn(asn, fsm)
      {asn, length + size}
    end)
  end

  defp encode_asn(asn, %FSM{four_octets: true}), do: {<<asn::32>>, 4}

  defp encode_asn(asn, _fsm) when asn > @asn_2octets_max,
    do: {<<@as_trans::16>>, 2}

  defp encode_asn(asn, _fsm), do: {<<asn::16>>, 2}

  defp encode_type(:as_set), do: 1
  defp encode_type(:as_sequence), do: 2
  defp encode_type(:as_confed_sequence), do: 3
  defp encode_type(:as_confed_set), do: 4
end
