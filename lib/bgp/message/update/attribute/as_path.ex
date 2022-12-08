defmodule BGP.Message.UPDATE.Attribute.ASPath do
  @moduledoc false

  alias BGP.FSM
  alias BGP.Message.{Encoder, NOTIFICATION}

  @type type :: :as_set | :as_sequence
  @type length :: non_neg_integer()
  @type t :: %__MODULE__{type: type(), length: length()}

  @enforce_keys [:type, :length]
  defstruct length: nil, type: nil, value: []

  @behaviour Encoder

  @impl Encoder
  def decode(<<type::8, length::8, asns::binary>>, fsm) do
    %__MODULE__{
      type: decode_type(type),
      length: length,
      value: decode_asns(asns, fsm, [])
    }
  end

  defp decode_type(1), do: :as_set
  defp decode_type(2), do: :as_sequence

  defp decode_asns(<<>>, _fsm, asns), do: Enum.reverse(asns)

  defp decode_asns(<<asn::32, rest::binary>>, %FSM{four_octets: true} = fsm, asns),
    do: decode_asns(rest, fsm, [asn | asns])

  defp decode_asns(<<asn::16, rest::binary>>, %FSM{four_octets: false} = fsm, asns),
    do: decode_asns(rest, fsm, [asn | asns])

  defp decode_asns(_data, _four_octets, _asns) do
    raise NOTIFICATION, code: :update_message
  end

  @impl Encoder
  def encode(%__MODULE__{type: type, length: length, value: value}, fsm) do
    asn_length = asn_length(fsm)

    {path, path_length} =
      Enum.map_reduce(value, 0, fn asn, path_length ->
        {<<asn::integer-size(asn_length)>>, path_length + div(asn_length, 8)}
      end)

    {
      [<<encode_type(type)::8>>, <<length::8>>, path],
      2 + path_length
    }
  end

  defp asn_length(%FSM{four_octets: true}), do: 32
  defp asn_length(%FSM{four_octets: false}), do: 16

  defp encode_type(:as_set), do: 1
  defp encode_type(:as_sequence), do: 2

  defp encode_type(_type) do
    raise NOTIFICATION, code: :update_message
  end
end
