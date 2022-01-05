defmodule BGP.Message do
  @moduledoc false

  alias BGP.Message.{Encoder, KEEPALIVE, NOTIFICATION, OPEN, UPDATE}

  @type t :: struct()

  @header_size 19
  @marker 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
  @max_size 4_096

  @behaviour BGP.Message.Encoder

  @impl Encoder
  def decode(<<@marker::128, length::16, type::8, msg::binary>>, options)
      when length >= @header_size and length <= @max_size do
    with {:ok, module} <- module_for_type(type),
         do: module.decode(msg, options)
  end

  def decode(_msg, _options),
    do: {:error, %Encoder.Error{code: :message_header, subcode: :bad_message_length}}

  @impl Encoder
  def encode(%module{} = message, options) do
    data = module.encode(message, options)
    length = @header_size + IO.iodata_length(data)
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
    {OPEN, 1},
    {UPDATE, 2},
    {NOTIFICATION, 3},
    {KEEPALIVE, 4},
    {ROUTE_REFRESH, 5}
  ]

  for {module, code} <- @messages do
    defp type_for_module(unquote(module)), do: unquote(code)
  end

  defp type_for_module(module), do: raise("Unknown message module #{module}")

  for {module, code} <- @messages do
    defp module_for_type(unquote(code)), do: {:ok, unquote(module)}
  end

  defp module_for_type(_code),
    do: {:error, %Encoder.Error{code: :message_header, subcode: :bad_message_type}}
end
