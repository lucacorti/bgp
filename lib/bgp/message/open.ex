defmodule BGP.Message.OPEN do
  @moduledoc false

  alias BGP.Message.Encoder
  alias BGP.Message.Encoder.Error
  alias BGP.Message.OPEN.Parameter
  alias BGP.Prefix

  @asn_min 1
  @asn_max :math.pow(2, 16) - 1
  @asn_four_octets_max :math.pow(2, 32) - 1
  @hold_time_min 3

  @type t :: %__MODULE__{
          asn: BGP.asn(),
          bgp_id: Prefix.t(),
          hold_time: BGP.hold_time(),
          parameters: [Parameter.t()]
        }
  @enforce_keys [:asn, :bgp_id, :hold_time]
  defstruct asn: nil, bgp_id: nil, hold_time: nil, parameters: []

  @behaviour Encoder

  @impl Encoder
  def decode(
        <<version::8, asn::16, hold_time::16, bgp_id::binary()-size(4), params_length::8,
          params::binary()-size(params_length)>>,
        options
      ) do
    with :ok <- check_asn(asn, options),
         :ok <- check_hold_time(hold_time),
         :ok <- check_version(version),
         {:ok, bgp_id} <-
           decode_bgp_id(bgp_id) do
      {
        :ok,
        %__MODULE__{
          asn: asn,
          bgp_id: bgp_id,
          hold_time: hold_time,
          parameters: decode_parameters(params, [], options)
        }
      }
    end
  end

  def decode(_keepalive, _options),
    do: {:error, %Error{code: :message_header, subcode: :bad_message_length}}

  defp check_asn(asn, options) do
    four_octets = Keyword.get(options, :four_octets, false)

    case {four_octets, asn} do
      {true, asn} when asn >= @asn_min and asn <= @asn_four_octets_max -> :ok
      {false, asn} when asn >= @asn_min and asn <= @asn_max -> :ok
      _ -> {:error, %Error{code: :open_message, subcode: :bad_peer_as}}
    end
  end

  defp check_hold_time(hold_time) when hold_time == 0 or hold_time >= @hold_time_min, do: :ok

  defp check_hold_time(_hold_time),
    do: {:error, %Error{code: :open_message, subcode: :unacceptable_hold_time}}

  defp check_version(4), do: :ok

  defp check_version(version) do
    {:error,
     %Error{
       code: :open_message,
       subcode: :unsupported_version_number,
       data: <<version::16>>
     }}
  end

  defp decode_bgp_id(bgp_id) do
    case Prefix.decode(bgp_id) do
      {:ok, prefix} ->
        {:ok, prefix}

      _error ->
        {:error, %Error{code: :open_message, subcode: :bad_bgp_identifier}}
    end
  end

  defp decode_parameters(<<>> = _data, params, _options), do: Enum.reverse(params)

  defp decode_parameters(
         <<type::8, param_length::8, parameter::binary()-size(param_length), rest::binary>>,
         parameters,
         options
       ) do
    with {:ok, parameter} <-
           Parameter.decode(<<type::8, param_length::8, parameter::binary()>>, options),
         do: decode_parameters(rest, [parameter | parameters], options)
  end

  @impl Encoder
  def encode(%__MODULE__{parameters: parameters} = msg, options) do
    with {:ok, bgp_id, 32} <- Prefix.encode(msg.bgp_id) do
      {data, length} = encode_parameters(parameters, options)
      [<<4::8>>, <<msg.asn::16>>, <<msg.hold_time::16>>, bgp_id, <<length::8>>, data]
    end
  end

  defp encode_parameters(parameters, options) do
    Enum.map_reduce(parameters, 0, fn parameter, total ->
      data = Parameter.encode(parameter, options)
      {data, total + IO.iodata_length(data)}
    end)
  end
end
