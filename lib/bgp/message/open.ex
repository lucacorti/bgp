defmodule BGP.Message.OPEN do
  @moduledoc false

  alias BGP.Message.Encoder
  alias BGP.Message.OPEN.Parameter
  alias BGP.Prefix

  @type t :: %__MODULE__{
          asn: BGP.asn(),
          bgp_id: Prefix.t(),
          hold_time: BGP.hold_time(),
          parameters: [Parameter.t()]
        }
  @enforce_keys [:asn, :bgp_id]
  defstruct asn: nil, bgp_id: nil, hold_time: 0, parameters: []

  @behaviour Encoder

  @impl Encoder
  def decode(
        <<4::8, asn::16, hold_time::16, bgp_id::binary()-size(4), params_length::8,
          params::binary()-size(params_length)>>,
        options
      ) do
    case Prefix.decode(bgp_id) do
      {:ok, prefix} ->
        {
          :ok,
          %__MODULE__{
            asn: asn,
            bgp_id: prefix,
            hold_time: hold_time,
            parameters: decode_parameters(params, [], options)
          }
        }

      _error ->
        {:error, %Encoder.Error{code: :open_message, subcode: :bad_bgp_identifier}}
    end
  end

  def decode(_data, _options), do: %Encoder.Error{code: :open_message}

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
    case Prefix.encode(msg.bgp_id) do
      {:ok, bgp_id, 32} ->
        {data, length} = encode_parameters(parameters, options)
        [<<4::8>>, <<msg.asn::16>>, <<msg.hold_time::16>>, bgp_id, <<length::8>>, data]

      _error ->
        :error
    end
  end

  defp encode_parameters(parameters, options) do
    Enum.map_reduce(parameters, 0, fn parameter, total ->
      data = Parameter.encode(parameter, options)
      {data, total + IO.iodata_length(data)}
    end)
  end
end
