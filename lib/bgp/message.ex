defmodule BGP.Message do
  @moduledoc false

  alias BGP.FSM
  alias BGP.Message.{KEEPALIVE, NOTIFICATION, OPEN, ROUTEREFRESH, UPDATE}

  @type t :: KEEPALIVE.t() | NOTIFICATION.t() | OPEN.t() | UPDATE.t() | ROUTEREFRESH.t()

  @header_size 19
  @marker 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
  @marker_size 128
  @max_size 4_096
  @extended_max_size 65_536

  @spec decode(binary(), FSM.t()) :: t()
  def decode(<<header::binary-size(@header_size), msg::binary>>, fsm) do
    {module, length} = decode_header(header)
    check_length(module, length, fsm)
    module.decode(msg, fsm)
  end

  defp decode_header(<<@marker::@marker_size, length::16, type::8>>)
       when length >= @header_size do
    {module_for_type(type), length}
  end

  defp decode_header(_header) do
    raise NOTIFICATION, code: :message_header, subcode: :connection_not_synchronized
  end

  defp check_length(module, length, _fsm)
       when module in [KEEPALIVE, OPEN] and length > @max_size do
    raise NOTIFICATION, code: :message_header, subcode: :bad_message_length, data: length
  end

  defp check_length(_module, length, %FSM{} = fsm)
       when (fsm.extended_message and length > @extended_max_size) or length > @max_size do
    raise NOTIFICATION, code: :message_header, subcode: :bad_message_length, data: length
  end

  defp check_length(_module, _length, _fsm), do: :ok

  @spec encode(t(), FSM.t()) :: iodata()
  def encode(%module{} = message, fsm) do
    {data, length} = module.encode(message, fsm)

    [
      <<@marker::@marker_size>>,
      <<@header_size + length::16>>,
      <<type_for_module(module)::8>>,
      data
    ]
  end

  @spec stream!(iodata(), FSM.t()) :: Enumerable.t() | no_return()
  def stream!(data, fsm) do
    Stream.unfold(data, fn
      <<_marker::@marker_size, length::16, _type::8, _rest::binary>> = data
      when byte_size(data) >= length ->
        msg = binary_part(data, 0, length)
        rest_size = byte_size(data) - length
        rest_data = binary_part(data, length, rest_size)
        {{rest_data, decode(msg, fsm)}, rest_data}

      <<>> ->
        nil

      data ->
        {{data, nil}, data}
    end)
  end

  messages = [
    {OPEN, 1},
    {UPDATE, 2},
    {NOTIFICATION, 3},
    {KEEPALIVE, 4},
    {ROUTEREFRESH, 5}
  ]

  for {module, type} <- messages do
    defp type_for_module(unquote(module)), do: unquote(type)
  end

  defp type_for_module(_module) do
    raise NOTIFICATION, code: :message_header, subcode: :bad_message_type
  end

  for {module, type} <- messages do
    defp module_for_type(unquote(type)), do: unquote(module)
  end

  defp module_for_type(type) do
    raise NOTIFICATION, code: :message_header, subcode: :bad_message_type, data: <<type::8>>
  end

  @spec decode_prefixes(binary()) :: [IP.Prefix.t()]
  def decode_prefixes(data), do: decode_prefixes(data, [])

  defp decode_prefixes(<<>>, prefixes), do: Enum.reverse(prefixes)

  defp decode_prefixes(
         <<
           length::8,
           prefix::binary-unit(1)-size(length),
           rest::binary
         >>,
         prefixes
       )
       when rem(length, 8) == 0,
       do: decode_prefixes(rest, [decode_prefix(length, prefix) | prefixes])

  defp decode_prefixes(
         <<
           length::8,
           prefix::binary-unit(1)-size(length + 8 - rem(length, 8)),
           rest::binary
         >>,
         prefixes
       ),
       do: decode_prefixes(rest, [decode_prefix(length, prefix) | prefixes])

  defp decode_prefix(length, prefix) do
    case IP.Address.from_binary(
           <<prefix::binary-unit(1)-size(length), 0::unit(1)-size(32 - length)>>
         ) do
      {:ok, address} ->
        IP.Prefix.new(address, length)

      {:error, _reason} ->
        raise NOTIFICATION, code: :update_message, data: prefix
    end
  end

  @spec encode_prefixes([IP.Prefix.t()]) :: {iodata(), pos_integer()}
  def encode_prefixes(prefixes) do
    Enum.map_reduce(prefixes, 0, fn prefix, length ->
      {data, data_length} = encode_prefix(prefix)
      {data, length + data_length}
    end)
  end

  def encode_prefix(prefix) do
    address = IP.Prefix.first(prefix)
    integer = IP.Address.to_integer(address)
    encoded = <<integer::unit(32)-size(1)>>
    length = IP.Prefix.length(prefix)
    padding = if rem(length, 8) > 0, do: 8 - rem(length, 8), else: 0

    {
      [<<length::8>>, <<encoded::binary-unit(1)-size(length), 0::unsigned-size(padding)>>],
      1 + div(length + padding, 8)
    }
  end
end
