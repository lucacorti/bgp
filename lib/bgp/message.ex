defmodule BGP.Message do
  @moduledoc false

  alias BGP.Message.{Encoder, KEEPALIVE, NOTIFICATION, OPEN, ROUTEREFRESH, UPDATE}

  @type t :: KEEPALIVE.t() | NOTIFICATION.t() | OPEN.t() | UPDATE.t() | ROUTEREFRESH.t()

  @header_size 19
  @marker 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
  @marker_size 128
  @max_size 4_096
  @extended_max_size 65_536

  @behaviour BGP.Message.Encoder

  @impl Encoder
  def decode(<<header::binary()-size(@header_size), msg::binary>>, options) do
    with {:ok, module, length} <- decode_header(header),
         :ok <- check_length(module, length, options),
         do: module.decode(msg, options)
  end

  defp decode_header(<<@marker::@marker_size, length::16, type::8>>)
       when length >= @header_size do
    with {:ok, module} <- module_for_type(type), do: {:ok, module, length}
  end

  defp decode_header(_header),
    do: {:error, %Encoder.Error{code: :message_header, subcode: :connection_not_synchronized}}

  defp check_length(module, length, _options)
       when module in [KEEPALIVE, OPEN] and length > @max_size do
    {:error, %Encoder.Error{code: :message_header, subcode: :bad_message_length, data: length}}
  end

  defp check_length(_module, length, options) do
    extended_message = Keyword.get(options, :extended_message)

    case {extended_message, length} do
      {extended, length} when (extended and length > @extended_max_size) or length > @max_size ->
        {:error,
         %Encoder.Error{code: :message_header, subcode: :bad_message_length, data: length}}

      _ ->
        :ok
    end
  end

  @impl Encoder
  def encode(%module{} = message, options) do
    data = module.encode(message, options)
    length = @header_size + IO.iodata_length(data)
    type = type_for_module(module)

    [<<@marker::@marker_size>>, <<length::16>>, <<type::8>>, data]
  end

  @spec stream!(iodata(), Encoder.options()) :: Enumerable.t() | no_return()
  def stream!(data, options) do
    Stream.unfold(data, fn
      <<marker::@marker_size, length::16, type::8, _rest::binary>> = data
      when byte_size(data) >= length ->
        with {:ok, module, length} <-
               decode_header(<<marker::@marker_size, length::16, type::8>>),
             :ok <- check_length(module, length, options) do
          msg_data = binary_part(data, 0, length)
          rest_size = byte_size(data) - length
          rest_data = binary_part(data, length, rest_size)

          {{rest_data, msg_data}, rest_data}
        else
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
