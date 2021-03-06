defmodule BGP.Message.UPDATE.Attribute do
  @moduledoc false

  alias BGP.Message.Encoder

  alias BGP.Message.UPDATE.Attribute.{
    Aggregator,
    AS4Aggregator,
    AS4Path,
    ASPath,
    AtomicAggregate,
    Communities,
    LargeCommunities,
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

    [<<IO.iodata_length(data)::16>>, <<type_for_module(module)::8>>, data]
  end

  attributes = [
    {Origin, 1},
    {ASPath, 2},
    {NextHop, 3},
    {MultiExitDisc, 4},
    {LocalPref, 5},
    {AtomicAggregate, 6},
    {Aggregator, 7},
    {Communities, 8},
    {ExtendedCommunities, 16},
    {AS4Path, 17},
    {AS4Aggregator, 18},
    {IPV6ExtendedCommunities, 25},
    {LargeCommunities, 32}
  ]

  for {module, code} <- attributes do
    defp type_for_module(unquote(module)), do: unquote(code)
  end

  defp type_for_module(module), do: raise("Unknown path attribute module #{module}")

  for {module, code} <- attributes do
    defp module_for_type(unquote(code)), do: unquote(module)
  end

  defp module_for_type(_code), do: {:error, :unknown}
end
