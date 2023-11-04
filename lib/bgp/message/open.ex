defmodule BGP.Message.OPEN do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.{
    Message,
    Message.Encoder,
    Message.NOTIFICATION,
    Message.OPEN.Capabilities,
    Server.Session
  }

  @as_trans 23_456
  @asn_max floor(:math.pow(2, 16)) - 1
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
          255::8, length::16, params::binary-size(length)>>,
        session
      ) do
    decode_open(
      version,
      asn,
      hold_time,
      bgp_id,
      params,
      %Session{session | extended_optional_parameters: true}
    )
  end

  def decode(
        <<version::8, asn::16, hold_time::16, bgp_id::binary-size(4), length::8,
          params::binary-size(length)>>,
        session
      ) do
    decode_open(version, asn, hold_time, bgp_id, params, session)
  end

  def decode(_keepalive, _session) do
    raise NOTIFICATION, code: :message_header, subcode: :bad_message_length
  end

  defp decode_open(version, asn, hold_time, bgp_id, params, %Session{} = session) do
    unless version == 4 do
      raise NOTIFICATION,
        code: :open_message,
        subcode: :unsupported_version_number,
        data: <<version::8>>
    end

    unless hold_time == 0 or hold_time >= @hold_time_min do
      raise NOTIFICATION,
        code: :open_message,
        subcode: :unacceptable_hold_time,
        data: <<hold_time::16>>
    end

    unless asn >= 1 and asn <= @asn_max do
      raise NOTIFICATION,
        code: :open_message,
        subcode: :bad_peer_as,
        data: <<asn::size(16)>>
    end

    decode_parameters(
      params,
      %__MODULE__{
        asn: asn,
        bgp_id: decode_bgp_id(bgp_id),
        hold_time: hold_time
      },
      session
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

  defp decode_parameters(<<>> = _data, open, session), do: {open, session}

  defp decode_parameters(
         <<2::8, length::16, parameter::binary-size(length), rest::binary>>,
         msg,
         %Session{extended_optional_parameters: true} = session
       ) do
    {capabilities, session} = Capabilities.decode(parameter, session)
    decode_parameters(rest, %__MODULE__{msg | capabilities: capabilities}, session)
  end

  defp decode_parameters(
         <<2::8, length::8, parameter::binary-size(length), rest::binary>>,
         msg,
         session
       ) do
    {capabilities, session} = Capabilities.decode(parameter, session)
    decode_parameters(rest, %__MODULE__{msg | capabilities: capabilities}, session)
  end

  @impl Encoder
  def encode(
        %__MODULE__{capabilities: capabilities} = msg,
        %Session{extended_optional_parameters: true} = session
      ) do
    {data, length, session} = encode_capabilities(capabilities, session)
    {bgp_id, 32} = Message.encode_address(msg.bgp_id)
    asn = if msg.asn < @asn_max, do: msg.asn, else: @as_trans

    {
      [
        <<4::8>>,
        <<asn::16>>,
        <<msg.hold_time::16>>,
        bgp_id,
        <<255::8, 255::8, length::16>>,
        data
      ],
      13 + length,
      session
    }
  end

  def encode(%__MODULE__{} = msg, session) do
    {data, length, session} = encode_capabilities(msg, session)
    {bgp_id, 32} = Message.encode_address(msg.bgp_id)
    asn = if msg.asn < @asn_max, do: msg.asn, else: @as_trans

    {
      [
        <<4::8>>,
        <<asn::16>>,
        <<msg.hold_time::16>>,
        bgp_id,
        <<length::8>>,
        data
      ],
      10 + length,
      session
    }
  end

  def encode_capabilities(
        %__MODULE__{capabilities: capabilities},
        %Session{extended_optional_parameters: true} = session
      ) do
    {data, length, session} = Capabilities.encode(capabilities, session)

    {
      [<<2::8>>, <<length::16>>, data],
      3 + length,
      session
    }
  end

  def encode_capabilities(%__MODULE__{capabilities: capabilities}, session) do
    {data, length, session} = Capabilities.encode(capabilities, session)

    {
      [<<2::8>>, <<length::8>>, data],
      2 + length,
      session
    }
  end
end
