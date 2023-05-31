defmodule BGP.Message do
  @moduledoc "BGP Message"

  alias BGP.FSM
  alias BGP.Message.{KEEPALIVE, NOTIFICATION, OPEN, ROUTEREFRESH, UPDATE}

  @type t :: KEEPALIVE.t() | NOTIFICATION.t() | OPEN.t() | UPDATE.t() | ROUTEREFRESH.t()

  @header_size 19
  @marker 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
  @marker_size 128
  @max_size 4_096
  @extended_max_size 65_535

  messages = [
    {OPEN, 1},
    {UPDATE, 2},
    {NOTIFICATION, 3},
    {KEEPALIVE, 4},
    {ROUTEREFRESH, 5}
  ]

  @spec decode(binary(), FSM.t()) :: {t(), FSM.t()} | no_return()
  def decode(<<@marker::@marker_size, length::16, type::8, msg::binary>>, %FSM{} = fsm)
      when length >= @header_size do
    case module_for_type(type) do
      {:ok, module} when module in [KEEPALIVE, OPEN] and length > @max_size ->
        raise NOTIFICATION,
          code: :message_header,
          subcode: :bad_message_length,
          data: <<length::16>>

      {:ok, _module}
      when (fsm.extended_message and length > @extended_max_size) or length > @max_size ->
        raise NOTIFICATION,
          code: :message_header,
          subcode: :bad_message_length,
          data: <<length::16>>

      {:ok, module} ->
        module.decode(msg, fsm)

      :error ->
        raise NOTIFICATION, code: :message_header, subcode: :bad_message_type, data: <<type::8>>
    end
  end

  def decode(_data, _fsm) do
    raise NOTIFICATION, code: :message_header, subcode: :connection_not_synchronized
  end

  @spec encode(t(), FSM.t()) :: {iodata(), FSM.t()} | no_return()
  def encode(%module{} = message, fsm) do
    case type_for_module(module) do
      {:ok, type} ->
        {data, length, fsm} = module.encode(message, fsm)

        {
          [
            <<@marker::@marker_size>>,
            <<@header_size + length::16>>,
            <<type::8>>,
            data
          ],
          fsm
        }

      :error ->
        raise NOTIFICATION, code: :message_header, subcode: :bad_message_type, data: module
    end
  end

  @spec stream!(iodata()) :: Enumerable.t() | no_return()
  def stream!(data) do
    Stream.unfold(data, fn
      <<_marker::@marker_size, length::16, _type::8, _rest::binary>> = data
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

  @spec decode_address(binary()) :: {:ok, IP.Address.t()} | {:error, binary}
  def decode_address(address_data) do
    case IP.Address.from_binary(address_data) do
      {:ok, address} -> {:ok, address}
      {:error, _reason} -> {:error, address_data}
    end
  end

  @spec decode_prefixes(binary()) :: {:ok, [IP.Prefix.t()]} | {:error, binary()}
  def decode_prefixes(data), do: decode_prefixes(data, [])

  defp decode_prefixes(<<>>, prefixes), do: {:ok, Enum.reverse(prefixes)}

  defp decode_prefixes(<<length::8, data::binary>>, prefixes) when rem(length, 8) == 0 do
    <<prefix_data::binary-unit(1)-size(length), rest::binary>> = data

    with {:ok, prefix} <- decode_prefix(length, prefix_data),
         do: decode_prefixes(rest, [prefix | prefixes])
  end

  defp decode_prefixes(<<length::8, data::binary>>, prefixes) do
    prefix_size = length + 8 - rem(length, 8)
    <<prefix_data::binary-unit(1)-size(prefix_size), rest::binary>> = data

    with {:ok, prefix} <- decode_prefix(length, prefix_data),
         do: decode_prefixes(rest, [prefix | prefixes])
  end

  @spec decode_prefix(pos_integer(), binary()) :: {:ok, IP.Prefix.t()} | {:error, binary()}
  def decode_prefix(length, prefix_data) do
    prefix_length = 32 - length

    with {:ok, address} <-
           decode_address(
             <<prefix_data::binary-unit(1)-size(length), 0::unit(1)-size(prefix_length)>>
           ),
         do: {:ok, IP.Prefix.new(address, length)}
  end

  @spec encode_address(IP.Address.t()) :: {binary(), pos_integer()}
  def encode_address(%IP.Address{version: 4} = address),
    do: {<<IP.Address.to_integer(address)::32>>, 32}

  def encode_address(%IP.Address{version: 6} = address),
    do: {<<IP.Address.to_integer(address)::128>>, 128}

  @spec encode_prefixes([IP.Prefix.t()]) :: {iodata(), pos_integer()}
  def encode_prefixes(prefixes) do
    Enum.map_reduce(prefixes, 0, fn prefix, length ->
      {data, data_length} = encode_prefix(prefix)
      {data, length + data_length}
    end)
  end

  @spec encode_prefix(IP.Prefix.t()) :: {iodata(), pos_integer()}
  def encode_prefix(prefix) do
    address = IP.Prefix.first(prefix)
    {encoded, _size} = encode_address(address)
    length = IP.Prefix.length(prefix)
    padding = if rem(length, 8) > 0, do: 8 - rem(length, 8), else: 0

    {
      [<<length::8>>, <<encoded::binary-unit(1)-size(length), 0::size(padding)>>],
      1 + div(length + padding, 8)
    }
  end

  for {module, type} <- messages do
    defp type_for_module(unquote(module)), do: {:ok, unquote(type)}
  end

  defp type_for_module(_module), do: :error

  for {module, type} <- messages do
    defp module_for_type(unquote(type)), do: {:ok, unquote(module)}
  end

  defp module_for_type(_type), do: :error
end
