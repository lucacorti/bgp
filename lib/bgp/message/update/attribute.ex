defmodule BGP.Message.Update.Attribute do
  @moduledoc false

  alias BGP.Message.Encoder

  alias BGP.Message.Update.Attribute.{
    Aggregator,
    ASPath,
    AtomicAggregate,
    LocalPref,
    MultiExitDisc,
    NextHop,
    Origin
  }

  @behaviour Encoder

  @impl Encoder
  def decode(<<code::8, data::binary>>, options),
    do: module_for_type(code).decode(data, options)

  @impl Encoder
  def encode(%module{} = message, options) do
    data = module.encode(message, options)
    length = IO.iodata_length(data)
    type = type_for_module(module)

    [<<length::16>>, <<type::8>>, data]
  end

  @attributes [
    {Origin, 1},
    {ASPath, 2},
    {NextHop, 3},
    {MultiExitDisc, 4},
    {LocalPref, 5},
    {AtomicAggregate, 6},
    {Aggregator, 7}
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
