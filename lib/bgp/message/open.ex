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

  @type asn :: pos_integer()
  @type bgp_id :: IP.Address.t()
  @type hold_time :: non_neg_integer()

  @type t :: %__MODULE__{
          asn: asn(),
          bgp_id: bgp_id(),
          hold_time: non_neg_integer(),
          capabilities: Capabilities.t()
        }
  @enforce_keys [:asn, :bgp_id, :hold_time]
  defstruct asn: nil, bgp_id: nil, hold_time: nil, capabilities: nil

  @behaviour Encoder

  @impl Encoder
  def decode(
        <<version::8, asn::16, hold_time::16, bgp_id::binary-size(4), _non_ext_params_length::8,
          255::8, length::16, params::binary-size(length)>>,
        %Session{} = session
      ) do
    capabilities = decode_parameters(params, true, [])
    decode_open(version, asn, hold_time, bgp_id, capabilities, session)
  end

  def decode(
        <<version::8, asn::16, hold_time::16, bgp_id::binary-size(4), length::8,
          params::binary-size(length)>>,
        %Session{} = session
      ) do
    capabilities = decode_parameters(params, false, [])
    decode_open(version, asn, hold_time, bgp_id, capabilities, session)
  end

  def decode(_keepalive, _session) do
    raise NOTIFICATION, code: :message_header, subcode: :bad_message_length
  end

  defp decode_open(version, asn, hold_time, bgp_id, capabilities, %Session{} = session) do
    if version != 4 do
      raise NOTIFICATION,
        code: :open_message,
        subcode: :unsupported_version_number,
        data: <<version::8>>
    end

    if !(hold_time == 0 or hold_time >= @hold_time_min) do
      raise NOTIFICATION,
        code: :open_message,
        subcode: :unacceptable_hold_time,
        data: <<hold_time::16>>
    end

    if !(asn >= 1 and asn <= @asn_max) do
      raise NOTIFICATION,
        code: :open_message,
        subcode: :bad_peer_as,
        data: <<asn::size(16)>>
    end

    %__MODULE__{
      asn: asn,
      bgp_id: decode_bgp_id(bgp_id),
      hold_time: hold_time,
      capabilities: Capabilities.decode(capabilities, session)
    }
  end

  defp decode_bgp_id(bgp_id) do
    case Message.decode_address(bgp_id) do
      {:ok, address} ->
        address

      {:error, data} ->
        raise NOTIFICATION, code: :open_message, subcode: :bad_bgp_identifier, data: data
    end
  end

  # Capabilities may be spread over multiple Optional Parameters (RFC 5492), collect
  # them all so they can be decoded at once. Extended parameters are RFC 9072.
  defp decode_parameters(<<>>, _extended, capabilities),
    do: IO.iodata_to_binary(Enum.reverse(capabilities))

  defp decode_parameters(
         <<2::8, length::16, parameter::binary-size(length), rest::binary>>,
         true = extended,
         capabilities
       ),
       do: decode_parameters(rest, extended, [parameter | capabilities])

  defp decode_parameters(
         <<2::8, length::8, parameter::binary-size(length), rest::binary>>,
         false = extended,
         capabilities
       ),
       do: decode_parameters(rest, extended, [parameter | capabilities])

  @impl Encoder
  def encode(%__MODULE__{} = msg, %Session{extended_optional_parameters: true} = session) do
    {data, length} = encode_capabilities(msg, session)
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
      13 + length
    }
  end

  def encode(%__MODULE__{} = msg, session) do
    {data, length} = encode_capabilities(msg, session)
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
      10 + length
    }
  end

  def encode_capabilities(
        %__MODULE__{capabilities: capabilities},
        %Session{extended_optional_parameters: true} = session
      ) do
    {data, length} = Capabilities.encode(capabilities, session)
    {[<<2::8>>, <<length::16>>, data], 3 + length}
  end

  def encode_capabilities(%__MODULE__{capabilities: capabilities}, session) do
    {data, length} = Capabilities.encode(capabilities, session)
    {[<<2::8>>, <<length::8>>, data], 2 + length}
  end
end
