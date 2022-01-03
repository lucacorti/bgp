defmodule BGP.Message do
  @moduledoc false

  alias BGP.Message.{Encoder, KeepAlive, Notification, Open, Update}

  @type t :: struct()

  @marker 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF

  @behaviour BGP.Message.Encoder

  @impl Encoder
  def decode(<<@marker::128, _length::16, type::8, msg::binary>>, options),
    do: module_for_type(type).decode(msg, options)

  @impl Encoder
  def encode(%module{} = message, options) do
    data = module.encode(message, options)
    length = 19 + IO.iodata_length(data)
    type = type_for_module(module)

    [<<@marker::128>>, <<length::16>>, <<type::8>>, data]
  end

  @spec stream(iodata()) :: Enumerable.t()
  def stream(data) do
    Stream.unfold(data, fn
      <<@marker::128, length::16, _type::8, _rest::binary>> = data
      when byte_size(data) >= length ->
        msg_data = binary_part(data, 0, length)
        rest_size = byte_size(data) - length
        rest_data = binary_part(data, length, rest_size)

        {{rest_data, msg_data}, rest_data}

      <<>> ->
        nil

      data ->
        {{data, nil}, data}
    end)
  end

  @messages [
    {Open, 1},
    {Update, 2},
    {Notification, 3},
    {KeepAlive, 4}
  ]

  for {module, code} <- @messages do
    defp type_for_module(unquote(module)), do: unquote(code)
  end

  defp type_for_module(module), do: raise("Unknown message module #{module}")

  for {module, code} <- @messages do
    defp module_for_type(unquote(code)), do: unquote(module)
  end

  defp module_for_type(code), do: raise("Unknown message type code #{code}")
end
