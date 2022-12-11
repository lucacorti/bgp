defmodule BGP.Message.OPEN do
  @moduledoc false

  alias BGP.{FSM, Message.Encoder}
  alias BGP.Message.{NOTIFICATION, OPEN.Parameter}

  @asn_min 1
  @asn_max :math.pow(2, 16) - 1
  @asn_four_octets_max :math.pow(2, 32) - 1
  @hold_time_min 3

  @type t :: %__MODULE__{
          asn: BGP.asn(),
          bgp_id: IP.Address.t(),
          hold_time: BGP.hold_time(),
          parameters: [Parameter.t()]
        }
  @enforce_keys [:asn, :bgp_id, :hold_time]
  defstruct asn: nil, bgp_id: nil, hold_time: nil, parameters: []

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

    %__MODULE__{
      asn: asn,
      bgp_id: decode_bgp_id(bgp_id),
      hold_time: hold_time,
      parameters: decode_parameters(params, [], fsm)
    }
  end

  defp decode_bgp_id(bgp_id) do
    case IP.Address.from_binary(bgp_id) do
      {:ok, prefix} ->
        prefix

      _error ->
        raise NOTIFICATION, code: :open_message, subcode: :bad_bgp_identifier
    end
  end

  defp decode_parameters(<<>> = _data, params, _fsm), do: Enum.reverse(params)

  defp decode_parameters(
         <<type::8, param_length::16, parameter::binary-size(param_length), rest::binary>>,
         parameters,
         %FSM{extended_optional_parameters: true} = fsm
       ) do
    parameter = Parameter.decode(<<type::8, param_length::16, parameter::binary>>, fsm)
    decode_parameters(rest, [parameter | parameters], fsm)
  end

  defp decode_parameters(
         <<type::8, param_length::8, parameter::binary-size(param_length), rest::binary>>,
         parameters,
         fsm
       ) do
    parameter = Parameter.decode(<<type::8, param_length::8, parameter::binary>>, fsm)
    decode_parameters(rest, [parameter | parameters], fsm)
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
        %__MODULE__{parameters: parameters} = msg,
        %FSM{extended_optional_parameters: true} = fsm
      ) do
    {data, length} = encode_parameters(parameters, fsm)

    bgp_id = IP.Address.to_integer(msg.bgp_id)

    {
      [
        <<4::8>>,
        <<msg.asn::16>>,
        <<msg.hold_time::16>>,
        <<bgp_id::32>>,
        <<255::8>>,
        <<255::8>>,
        <<length::16>>,
        data
      ],
      13 + length
    }
  end

  def encode(%__MODULE__{parameters: parameters} = msg, fsm) do
    {data, length} = encode_parameters(parameters, fsm)

    bgp_id = IP.Address.to_integer(msg.bgp_id)

    {
      [<<4::8>>, <<msg.asn::16>>, <<msg.hold_time::16>>, <<bgp_id::32>>, <<length::8>>, data],
      10 + length
    }
  end

  defp encode_parameters(parameters, fsm) do
    Enum.map_reduce(parameters, 0, fn parameter, total ->
      {data, length} = Parameter.encode(parameter, fsm)
      {data, total + length}
    end)
  end
end
