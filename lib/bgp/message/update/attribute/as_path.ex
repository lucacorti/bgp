defmodule BGP.Message.UPDATE.Attribute.ASPath do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.FSM
  alias BGP.Message.{Encoder, NOTIFICATION}

  @type type :: :as_set | :as_sequence | :as_confed_sequence | :as_confed_set
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

  defp decode_path(<<type::8, length::8, data::binary>>, fsm, path) do
    asns_length = length * div(asn_length(fsm), 8)
    <<asns::binary-size(asns_length), rest::binary>> = data
    decode_path(rest, fsm, [{decode_type(type), length, decode_asns(asns, [])} | path])
  end

  defp decode_path(data, _fsm, _path) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_as_path, data: data
  end

  defp decode_type(1), do: :as_set
  defp decode_type(2), do: :as_sequence
  defp decode_type(3), do: :as_confed_sequence
  defp decode_type(4), do: :as_confed_set

  defp decode_asns(<<>>, asns), do: Enum.reverse(asns)

  defp decode_asns(<<asn::16, rest::binary>>, asns),
    do: decode_asns(rest, [asn | asns])

  @impl Encoder
  def encode(%__MODULE__{value: value}, %FSM{four_octets: four_octets} = fsm) do
    asn_length = asn_length(fsm)

    {data, length} =
      Enum.map_reduce(value, 0, fn {type, length, asns}, path_length ->
        {
          [
            <<encode_type(type)::8>>,
            <<length::8>>,
            Enum.map(asns, fn
              asn when not four_octets and asn > @asn_2octets_max ->
                <<@as_trans::size(asn_length)>>

              asn ->
                <<asn::size(asn_length)>>
            end)
          ],
          path_length + 2 + length * div(asn_length, 8)
        }
      end)

    {data, length, fsm}
  end

  defp encode_type(:as_set), do: 1
  defp encode_type(:as_sequence), do: 2
  defp encode_type(:as_confed_sequence), do: 3
  defp encode_type(:as_confed_set), do: 4

  defp asn_length(%FSM{four_octets: false}), do: 16
  defp asn_length(%FSM{four_octets: true}), do: 32
end
