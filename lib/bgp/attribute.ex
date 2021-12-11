defmodule BGP.Attribute do
  alias BGP.Attribute.{
    ASPath,
    Aggregator,
    AtomicAggregate,
    Flags,
    LocalPref,
    MultiExitDisc,
    NextHop,
    Origin
  }

  @type t :: struct()
  @type data :: iodata()
  @type length :: non_neg_integer()

  @callback decode(data()) :: {:ok, t()} | {:error, :decode_error}
  @callback encode(t()) :: data()

  @spec decode(data()) :: {:ok, t()} | {:error, :decode_error}
  def decode(<<flags::binary-size(1), type::8, rest::binary>>) do
    with {:ok, %Flags{extended: extended}} <- Flags.decode(flags) do
      length = if extended, do: 2, else: 1
      data = binary_part(rest, 0, length)
      module_for_type(type).decode(data)
    end
  end

  @spec encode(t()) :: iodata()
  def encode(%module{} = message) do
    data = module.encode(message)
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
