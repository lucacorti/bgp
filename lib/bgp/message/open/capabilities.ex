defmodule BGP.Message.OPEN.Capabilities do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.Message.AFN
  alias BGP.Message.{Encoder, NOTIFICATION}
  alias BGP.Server.Session

  @asn_four_octets_max floor(:math.pow(2, 32)) - 1

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
  def decode(data, session) do
    decode_capabilities(data, %__MODULE__{}, session)
  end

  defp decode_capabilities(<<>>, capabilities, session), do: {capabilities, session}

  defp decode_capabilities(
         <<code::8, length::8, value::binary-size(length), rest::binary>>,
         capabilities,
         session
       ) do
    {capabilities, session} = decode_capability(code, value, capabilities, session)
    decode_capabilities(rest, capabilities, session)
  end

  defp decode_capability(1, <<afi::16, _reserved::8, safi::8>>, capabilities, session) do
    with {:ok, afi} <- AFN.decode_afi(afi),
         {:ok, safi} <- AFN.decode_safi(safi) do
      {%__MODULE__{capabilities | multi_protocol: {afi, safi}}, session}
    else
      :error ->
        raise NOTIFICATION, code: :open_message
    end
  end

  defp decode_capability(2, <<>>, capabilities, session),
    do: {%__MODULE__{capabilities | route_refresh: true}, session}

  defp decode_capability(6, <<>>, capabilities, session),
    do: {%__MODULE__{capabilities | extended_message: true}, session}

  defp decode_capability(
         64,
         <<restarted::1, _reserved::3, time::12, afs::binary>>,
         capabilities,
         session
       ),
       do:
         {%__MODULE__{
            capabilities
            | graceful_restart: {restarted == 1, time, decode_afs(afs, [])}
          }, session}

  defp decode_capability(65, <<asn::32>>, capabilities, session) do
    unless asn >= 1 and asn <= @asn_four_octets_max do
      raise NOTIFICATION,
        code: :open_message,
        subcode: :bad_peer_as,
        data: <<asn::size(32)>>
    end

    {%__MODULE__{capabilities | four_octets_asn: true},
     %Session{session | four_octets: true, ibgp: asn == session.asn}}
  end

  defp decode_capability(70, <<>>, capabilities, session),
    do: {%__MODULE__{capabilities | enanched_route_refresh: true}, session}

  defp decode_capability(_code, _data, _capabilities, _session) do
    raise NOTIFICATION, code: :open_message
  end

  defp decode_afs(<<>>, afs), do: Enum.reverse(afs)

  defp decode_afs(<<afi::16, safi::8, forwarding::1, _reserved::7, rest::binary>>, afs) do
    with {:ok, afi} <- AFN.decode_afi(afi),
         {:ok, safi} <- AFN.decode_safi(safi) do
      decode_afs(rest, [{afi, safi, forwarding == 1} | afs])
    else
      :error ->
        raise NOTIFICATION, code: :open_message
    end
  end

  @impl Encoder
  def encode(%__MODULE__{} = capabilities, session) do
    {data, {length, session}} =
      [
        &encode_multi_protocol/2,
        &encode_route_refresh/2,
        &encode_extended_message/2,
        &encode_graceful_restart/2,
        &encode_four_octets_asn/2,
        &encode_enanched_route_refresh/2
      ]
      |> Enum.map_reduce({0, session}, fn encoder, {length, session} ->
        {data, capability_length} = encoder.(capabilities, session)

        {
          data,
          {length + capability_length, session}
        }
      end)

    {data, length, session}
  end

  defp encode_multi_protocol(%__MODULE__{multi_protocol: {afi, safi}}, _session) do
    with {:ok, afi} <- AFN.encode_afi(afi),
         {:ok, safi} <- AFN.encode_safi(safi) do
      {[<<1::8>>, <<4::8>>, <<afi::16>>, <<0::8>>, <<safi::8>>], 6}
    else
      :error -> raise NOTIFICATION, code: :open_message
    end
  end

  defp encode_multi_protocol(%__MODULE__{multi_protocol: nil}, _session), do: {[], 0}

  defp encode_route_refresh(%__MODULE__{route_refresh: true}, _session),
    do: {[<<2::8>>, <<0::8>>], 2}

  defp encode_route_refresh(%__MODULE__{route_refresh: false}, _session), do: {[], 0}

  defp encode_extended_message(%__MODULE__{extended_message: true}, _session),
    do: {[<<6::8>>, <<0::8>>], 2}

  defp encode_extended_message(%__MODULE__{extended_message: false}, _session), do: {[], 0}

  defp encode_graceful_restart(%__MODULE__{graceful_restart: {restarted, time, afs}}, _session) do
    {afs, length} = encode_afs(afs)
    {[<<if(restarted, do: 1, else: 0)::1>>, <<0::3>>, <<time::12>>, afs], 2 + length}
  end

  defp encode_graceful_restart(%__MODULE__{graceful_restart: nil}, _session), do: {[], 0}

  defp encode_four_octets_asn(%__MODULE__{four_octets_asn: true}, session),
    do: {[<<65::8>>, <<4::8>>, <<session.asn::32>>], 6}

  defp encode_four_octets_asn(%__MODULE__{four_octets_asn: false}, _session), do: {[], 0}

  defp encode_enanched_route_refresh(%__MODULE__{enanched_route_refresh: true}, _session),
    do: {[<<70::8>>, <<0::8>>], 2}

  defp encode_enanched_route_refresh(%__MODULE__{enanched_route_refresh: false}, _session),
    do: {[], 0}

  defp encode_afs(afs) do
    Enum.map_reduce(afs, 0, fn {afi, safi, forwarding}, length ->
      with {:ok, afi} <- AFN.encode_afi(afi),
           {:ok, safi} <- AFN.encode_safi(safi) do
        {<<afi::16, safi::8, forwarding::1, 0::7>>, length + 4}
      else
        :error ->
          raise NOTIFICATION, code: :open_message
      end
    end)
  end
end
