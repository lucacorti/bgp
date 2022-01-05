defmodule BGP.Message do
  @moduledoc false

  alias BGP.Message.{Encoder, KEEPALIVE, NOTIFICATION, OPEN, ROUTEREFRESH, UPDATE}

  @type t :: KEEPALIVE.t() | NOTIFICATION.t() | OPEN.t() | UPDATE.t() | ROUTEREFRESH.t()

  @header_size 19
  @marker 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
  @marker_size 128
  @max_size 4_096

  @behaviour BGP.Message.Encoder

  @impl Encoder
  def decode(<<header::binary()-size(@header_size), msg::binary>>, options) do
    with {:ok, module} <- decode_header(header),
         do: module.decode(msg, options)
  end

  defp decode_header(<<_marker::@marker_size, length::16, _type::8>>)
       when length < @header_size or length > @max_size do
    {:error, %Encoder.Error{code: :message_header, subcode: :bad_message_length, data: length}}
  end

  defp decode_header(<<@marker::@marker_size, _length::16, type::8>>), do: module_for_type(type)

  defp decode_header(_header),
    do: {:error, %Encoder.Error{code: :message_header, subcode: :connection_not_synchronized}}

  @impl Encoder
  def encode(%module{} = message, options) do
    data = module.encode(message, options)
    length = @header_size + IO.iodata_length(data)
    type = type_for_module(module)

    [<<@marker::@marker_size>>, <<length::16>>, <<type::8>>, data]
  end

  @spec stream!(iodata()) :: Enumerable.t() | no_return()
  def stream!(data) do
    Stream.unfold(data, fn
      <<@marker::@marker_size, length::16, type::8, _rest::binary>> = data
      when byte_size(data) >= length ->
        case decode_header(<<@marker::@marker_size, length::16, type::8>>) do
          {:ok, _module} ->
            msg_data = binary_part(data, 0, length)
            rest_size = byte_size(data) - length
            rest_data = binary_part(data, length, rest_size)

            {{rest_data, msg_data}, rest_data}

          {:error, error} ->
            throw(error)
        end

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
    {ROUTEREFRESH, 5}
  ]

  for {module, type} <- @messages do
    defp type_for_module(unquote(module)), do: unquote(type)
  end

  defp type_for_module(module), do: raise("Unknown message module #{module}")

  for {module, type} <- @messages do
    defp module_for_type(unquote(type)), do: {:ok, unquote(module)}
  end

  defp module_for_type(type) do
    {
      :error,
      %Encoder.Error{code: :message_header, subcode: :bad_message_type, data: <<type::8>>}
    }
  end
end
