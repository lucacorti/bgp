defmodule BGP.Message.OPEN.Capabilities do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.FSM
  alias BGP.Message.AFN
  alias BGP.Message.{Encoder, NOTIFICATION}

  @type t :: %__MODULE__{
          enanched_route_refresh: boolean(),
          extended_message: boolean(),
          four_octets_asn: boolean(),
          graceful_restart:
            {
              restarted :: boolean(),
              time :: integer(),
              afs :: [{AFN.afi(), AFN.safi(), forwarding :: boolean()}]
            }
            | nil,
          multi_protocol: {AFN.afi(), AFN.safi()} | nil,
          route_refresh: boolean()
        }

  defstruct enanched_route_refresh: false,
            extended_message: false,
            four_octets_asn: false,
            graceful_restart: nil,
            multi_protocol: nil,
            route_refresh: false

  @behaviour Encoder

  @impl Encoder
  def decode(data, fsm) do
    decode_capabilities(data, %__MODULE__{}, fsm)
  end

  defp decode_capabilities(<<>>, capabilities, fsm), do: {capabilities, fsm}

  defp decode_capabilities(
         <<code::8, length::8, value::binary-size(length), rest::binary>>,
         capabilities,
         fsm
       ) do
    {capabilities, fsm} = decode_capability(code, value, capabilities, fsm)
    decode_capabilities(rest, capabilities, fsm)
  end

  defp decode_capability(1, <<afi::16, _reserved::8, safi::8>>, capabilities, fsm),
    do: {%__MODULE__{capabilities | multi_protocol: {decode_afi(afi), decode_safi(safi)}}, fsm}

  defp decode_capability(2, <<>>, capabilities, fsm),
    do: {%__MODULE__{capabilities | route_refresh: true}, fsm}

  defp decode_capability(6, <<>>, capabilities, fsm),
    do: {%__MODULE__{capabilities | extended_message: true}, fsm}

  defp decode_capability(
         64,
         <<restarted::1, _reserved::3, time::12, afs::binary>>,
         capabilities,
         fsm
       ),
       do:
         {%__MODULE__{
            capabilities
            | graceful_restart: {restarted == 1, time, decode_afs(afs, [])}
          }, fsm}

  defp decode_capability(65, <<asn::32>>, capabilities, fsm),
    do:
      {%__MODULE__{capabilities | four_octets_asn: true},
       %FSM{fsm | four_octets: true, ibgp: asn == fsm.asn}}

  defp decode_capability(70, <<>>, capabilities, fsm),
    do: {%__MODULE__{capabilities | enanched_route_refresh: true}, fsm}

  defp decode_capability(_code, _data, _capabilities, _fsm) do
    raise NOTIFICATION, code: :open_message
  end

  defp decode_afs(<<>>, afs), do: Enum.reverse(afs)

  defp decode_afs(<<afi::16, safi::8, forwarding::1, _reserved::7, rest::binary>>, afs),
    do: decode_afs(rest, [{decode_afi(afi), decode_safi(safi), forwarding == 1} | afs])

  defp decode_afi(afi) do
    case AFN.decode_afi(afi) do
      {:ok, afi} -> afi
      :error -> raise NOTIFICATION, code: :open_message
    end
  end

  defp decode_safi(safi) do
    case AFN.decode_safi(safi) do
      {:ok, safi} -> safi
      :error -> raise NOTIFICATION, code: :open_message
    end
  end

  @impl Encoder
  def encode(%__MODULE__{} = capabilities, fsm) do
    {data, {length, fsm}} =
      [
        &encode_multi_protocol/2,
        &encode_route_refresh/2,
        &encode_extended_message/2,
        &encode_graceful_restart/2,
        &encode_four_octets_asn/2,
        &encode_enanched_route_refresh/2
      ]
      |> Enum.map_reduce({0, fsm}, fn encoder, {length, fsm} ->
        {data, capability_length} = encoder.(capabilities, fsm)

        {
          data,
          {length + capability_length, fsm}
        }
      end)

    {data, length, fsm}
  end

  defp encode_multi_protocol(%__MODULE__{multi_protocol: {afi, safi}}, _fsm),
    do: {[<<1::8>>, <<4::8>>, <<encode_afi(afi)::16>>, <<0::8>>, <<encode_safi(safi)::8>>], 6}

  defp encode_multi_protocol(%__MODULE__{multi_protocol: nil}, _fsm), do: {[], 0}

  defp encode_route_refresh(%__MODULE__{route_refresh: true}, _fsm), do: {[<<2::8>>, <<0::8>>], 2}
  defp encode_route_refresh(%__MODULE__{route_refresh: false}, _fsm), do: {[], 0}

  defp encode_extended_message(%__MODULE__{extended_message: true}, _fsm),
    do: {[<<6::8>>, <<0::8>>], 2}

  defp encode_extended_message(%__MODULE__{extended_message: false}, _fsm), do: {[], 0}

  defp encode_graceful_restart(%__MODULE__{graceful_restart: {_restarted, _time, _afns}}, _fsm),
    do: {[], 0}

  defp encode_graceful_restart(%__MODULE__{graceful_restart: nil}, _fsm), do: {[], 0}

  defp encode_four_octets_asn(%__MODULE__{four_octets_asn: true}, fsm),
    do: {[<<65::8>>, <<4::8>>, <<fsm.asn::32>>], 6}

  defp encode_four_octets_asn(%__MODULE__{four_octets_asn: false}, _fsm), do: {[], 0}

  defp encode_enanched_route_refresh(%__MODULE__{enanched_route_refresh: true}, _fsm),
    do: {[<<70::8>>, <<0::8>>], 2}

  defp encode_enanched_route_refresh(%__MODULE__{enanched_route_refresh: false}, _fsm),
    do: {[], 0}

  defp encode_afi(afi) do
    case AFN.encode_afi(afi) do
      {:ok, afi} -> afi
      :error -> raise NOTIFICATION, code: :open_message
    end
  end

  defp encode_safi(safi) do
    case AFN.encode_safi(safi) do
      {:ok, safi} -> safi
      :error -> raise NOTIFICATION, code: :open_message
    end
  end
end
