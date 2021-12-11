defmodule BGP.Message.Open do
  @type t :: %__MODULE__{
          asn: pos_integer(),
          bgp_id: pos_integer(),
          hold_time: non_neg_integer(),
          parameters: [any()]
        }
  @enforce_keys [:asn, :bgp_id]
  defstruct asn: nil, bgp_id: nil, hold_time: 0, parameters: []

  alias BGP.Message

  @behaviour Message

  @impl Message
  def decode(
        <<4::8, asn::16, hold_time::16, bgp_id::32, params_length::8, params::binary>>,
        _length
      ) do
    {
      :ok,
      decode_params(
        %__MODULE__{asn: asn, bgp_id: bgp_id, hold_time: hold_time},
        params_length,
        params
      )
    }
  end

  defp decode_params(%__MODULE__{} = msg, 0 = _params_length, _params), do: msg

  defp decode_params(
         %__MODULE__{} = msg,
         params_length,
         <<type::8, param_length::8, params::binary>>
       ) do
    param = binary_part(params, 0, param_length)
    params = binary_part(params, param_length - 1, params_length - 1)

    msg
    |> decode_param(type, param)
    |> decode_params(params_length - param_length, params)
  end

  defp decode_param(msg, _type, _param), do: msg

  @impl Message
  def encode(%__MODULE__{} = msg),
    do: [<<4::8>>, <<msg.asn::16>>, <<msg.hold_time::16>>, <<msg.bgp_id::32>>, <<0::8>>]
end
