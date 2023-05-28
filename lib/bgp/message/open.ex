defmodule BGP.Message.OPEN do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.{FSM, Message, Message.Encoder, Message.NOTIFICATION, Message.OPEN.Capabilities}

  @asn_min 1
  @asn_max :math.pow(2, 16) - 1
  @asn_four_octets_max :math.pow(2, 32) - 1
  @hold_time_min 3

  @type t :: %__MODULE__{
          asn: BGP.asn(),
          bgp_id: IP.Address.t(),
          hold_time: BGP.hold_time(),
          capabilities: Capabilities.t()
        }
  @enforce_keys [:asn, :bgp_id, :hold_time]
  defstruct asn: nil, bgp_id: nil, hold_time: nil, capabilities: nil

  @behaviour Encoder

  @impl Encoder
  def decode(
        <<version::8, asn::16, hold_time::16, bgp_id::binary-size(4), _non_ext_params_length::8,
          255::8, params_length::16, params::binary-size(params_length)>>,
        fsm
      ) do
    decode_open(
      version,
      asn,
      hold_time,
      bgp_id,
      params,
      %FSM{fsm | extended_optional_parameters: true}
    )
  end

  def decode(
        <<version::8, asn::16, hold_time::16, bgp_id::binary-size(4), params_length::8,
          params::binary-size(params_length)>>,
        fsm
      ),
      do: decode_open(version, asn, hold_time, bgp_id, params, fsm)

  def decode(_keepalive, _fsm) do
    raise NOTIFICATION, code: :message_header, subcode: :bad_message_length
  end

  defp decode_open(version, asn, hold_time, bgp_id, params, fsm) do
    check_asn(asn, fsm)
    check_hold_time(hold_time)
    check_version(version)

    decode_parameters(
      params,
      %__MODULE__{
        asn: asn,
        bgp_id: decode_bgp_id(bgp_id),
        hold_time: hold_time
      },
      fsm
    )
  end

  defp decode_bgp_id(bgp_id) do
    case Message.decode_address(bgp_id) do
      {:ok, address} ->
        address

      {:error, data} ->
        raise NOTIFICATION, code: :open_message, subcode: :bad_bgp_identifier, data: data
    end
  end

  defp decode_parameters(<<>> = _data, open, fsm), do: {open, fsm}

  defp decode_parameters(
         <<2::8, param_length::16, parameter::binary-size(param_length), rest::binary>>,
         msg,
         %FSM{extended_optional_parameters: true} = fsm
       ) do
    {capabilities, fsm} = Capabilities.decode(parameter, fsm)
    decode_parameters(rest, %__MODULE__{msg | capabilities: capabilities}, fsm)
  end

  defp decode_parameters(
         <<2::8, param_length::8, parameter::binary-size(param_length), rest::binary>>,
         msg,
         fsm
       ) do
    {capabilities, fsm} = Capabilities.decode(parameter, fsm)
    decode_parameters(rest, %__MODULE__{msg | capabilities: capabilities}, fsm)
  end

  defp check_asn(asn, %FSM{four_octets: true})
       when asn >= @asn_min and asn <= @asn_four_octets_max,
       do: :ok

  defp check_asn(asn, %FSM{four_octets: false}) when asn >= @asn_min and asn <= @asn_max,
    do: :ok

  defp check_asn(_asn, _fsm) do
    raise NOTIFICATION, code: :open_message, subcode: :bad_peer_as
  end

  defp check_hold_time(hold_time) when hold_time == 0 or hold_time >= @hold_time_min, do: :ok

  defp check_hold_time(_hold_time) do
    raise NOTIFICATION, code: :open_message, subcode: :unacceptable_hold_time
  end

  defp check_version(4), do: :ok

  defp check_version(version) do
    raise NOTIFICATION,
      code: :open_message,
      subcode: :unsupported_version_number,
      data: <<version::16>>
  end

  @impl Encoder
  def encode(
        %__MODULE__{capabilities: capabilities} = msg,
        %FSM{extended_optional_parameters: true} = fsm
      ) do
    {data, length, fsm} = encode_capabilities(capabilities, fsm)

    {
      [
        <<4::8>>,
        <<msg.asn::16>>,
        <<msg.hold_time::16>>,
        <<IP.Address.to_integer(msg.bgp_id)::32>>,
        <<255::8>>,
        <<255::8>>,
        <<length::16>>,
        data
      ],
      13 + length,
      fsm
    }
  end

  def encode(%__MODULE__{} = msg, fsm) do
    {data, length, fsm} = encode_capabilities(msg, fsm)

    {
      [
        <<4::8>>,
        <<msg.asn::16>>,
        <<msg.hold_time::16>>,
        <<IP.Address.to_integer(msg.bgp_id)::32>>,
        <<length::8>>,
        data
      ],
      10 + length,
      fsm
    }
  end

  def encode_capabilities(
        %__MODULE__{capabilities: capabilities},
        %FSM{extended_optional_parameters: true} = fsm
      ) do
    {data, length, fsm} = Capabilities.encode(capabilities, fsm)

    {
      [<<2::8>>, <<length::16>>, data],
      3 + length,
      fsm
    }
  end

  def encode_capabilities(%__MODULE__{capabilities: capabilities}, fsm) do
    {data, length, fsm} = Capabilities.encode(capabilities, fsm)

    {
      [<<2::8>>, <<length::8>>, data],
      2 + length,
      fsm
    }
  end
end
