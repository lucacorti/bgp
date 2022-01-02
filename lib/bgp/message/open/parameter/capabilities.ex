defmodule BGP.Message.Open.Parameter.Capabilities do
  @moduledoc false

  alias BGP.Message.Encoder

  alias BGP.Message.Open.Parameter.Capabilities.{
    FourOctetsASN,
    GracefulRestart,
    MultiProtocol,
    RouteRefresh
  }

  @type t :: %__MODULE__{capabilities: [struct()]}

  @enforce_keys [:capabilities]
  defstruct capabilities: []

  @behaviour Encoder

  @impl Encoder
  def decode(capabilities),
    do: {:ok, %__MODULE__{capabilities: decode_capabilities(capabilities, [])}}

  defp decode_capabilities(<<>>, capabilities), do: Enum.reverse(capabilities)

  defp decode_capabilities(
         <<code::8, length::8, value::binary()-size(length), rest::binary()>>,
         capabilities
       ) do
    with {:ok, capability} <- module_for_type(code).decode(value),
         do: decode_capabilities(rest, [capability | capabilities])
  end

  @impl Encoder
  def encode(%__MODULE__{capabilities: capabilities}) do
    Enum.map(capabilities, fn %module{} = capability ->
      data = module.encode(capability)
      length = IO.iodata_length(data)
      type = type_for_module(module)
      [<<type::8>>, <<length::8>>, data]
    end)
  end

  @attributes [
    {MultiProtocol, 1},
    {RouteRefresh, 2},
    {GracefulRestart, 64},
    {FourOctetsASN, 65}
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
