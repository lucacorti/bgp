defmodule BGP.Message do
  alias BGP.Message.{KeepAlive, Notification, Open, Update}

  @type t :: struct()
  @type data :: iodata()
  @type length :: non_neg_integer()

  @marker 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF

  @callback decode(data(), length()) :: {:ok, t()} | {:error, :decode_error}
  @callback encode(t()) :: data()

  @spec decode(data()) :: {:ok, t()} | {:error, :decode_error}
  def decode(<<@marker::128, length::16, type::8, rest::binary>>) do
    data = binary_part(rest, 0, length)
    module_for_type(type).decode(data, length)
  end

  @spec encode(t()) :: iodata()
  def encode(%module{} = message) do
    data = module.encode(message)
    length = IO.iodata_length(data)
    type = type_for_module(module)

    [<<@marker::128>>, <<length::16>>, <<type::8>>, data]
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
