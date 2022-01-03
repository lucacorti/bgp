defmodule BGP.Message.Open.Parameter do
  @moduledoc false

  alias BGP.Message.Encoder
  alias BGP.Message.Open.Parameter.Capabilities

  @behaviour Encoder

  @impl Encoder
  def decode(<<type::8, length::8, data::binary()-size(length)>>, options),
    do: module_for_type(type).decode(data, options)

  @impl Encoder
  def encode(%module{} = message, options) do
    data = module.encode(message, options)
    length = IO.iodata_length(data)
    type = type_for_module(module)

    [<<type::8>>, <<length::8>>, data]
  end

  @attributes [
    {Capabilities, 2}
  ]

  for {module, code} <- @attributes do
    defp type_for_module(unquote(module)), do: unquote(code)
  end

  defp type_for_module(module), do: raise("Unknown path attribute module #{module}")

  for {module, code} <- @attributes do
    defp module_for_type(unquote(code)), do: unquote(module)
  end

  defp module_for_type(code), do: raise("Unknown path attribute type code #{code}")
end
