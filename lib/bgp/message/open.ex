defmodule BGP.Message.Open do
  @moduledoc false

  alias BGP.Message.Encoder
  alias BGP.Message.Open.Parameter
  alias BGP.Prefix

  @type t :: %__MODULE__{
          asn: pos_integer(),
          bgp_id: Prefix.t(),
          hold_time: non_neg_integer(),
          parameters: [any()]
        }
  @enforce_keys [:asn, :bgp_id]
  defstruct asn: nil, bgp_id: nil, hold_time: 0, parameters: []

  @behaviour Encoder

  @impl Encoder
  def decode(
        <<4::8, asn::16, hold_time::16, bgp_id::binary()-size(4), params_length::8,
          params::binary()-size(params_length)>>
      ) do
    case Prefix.decode(bgp_id) do
      {:ok, prefix} ->
        {
          :ok,
          %__MODULE__{
            asn: asn,
            bgp_id: prefix,
            hold_time: hold_time,
            parameters: decode_parameters(params, [])
          }
        }

      _error ->
        :error
    end
  end

  defp decode_parameters(<<>> = _data, params), do: Enum.reverse(params)

  defp decode_parameters(
         <<type::8, param_length::8, parameter::binary()-size(param_length), rest::binary>>,
         parameters
       ) do
    with {:ok, paramter} <- Parameter.decode(<<type::8, param_length::8, parameter::binary()>>),
         do: decode_parameters(rest, [paramter | parameters])
  end

  @impl Encoder
  def encode(%__MODULE__{parameters: parameters} = msg) do
    case Prefix.encode(msg.bgp_id) do
      {:ok, bgp_id, 32} ->
        {data, length} = encode_parameters(parameters)
        [<<4::8>>, <<msg.asn::16>>, <<msg.hold_time::16>>, bgp_id, <<length::8>>, data]

      _error ->
        :error
    end
  end

  defp encode_parameters(parameters) do
    Enum.map_reduce(parameters, 0, fn parameter, total ->
      data = Parameter.encode(parameter)
      {data, total + IO.iodata_length(data)}
    end)
  end
end
