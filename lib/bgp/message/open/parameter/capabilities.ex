defmodule BGP.Message.OPEN.Parameter.Capabilities do
  @moduledoc false

  alias BGP.Message.Encoder

  alias BGP.Message.OPEN.Parameter.Capabilities.{
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
  def decode(capabilities, options),
    do: {:ok, %__MODULE__{capabilities: decode_capabilities(capabilities, [], options)}}

  defp decode_capabilities(<<>>, capabilities, _options), do: Enum.reverse(capabilities)

  defp decode_capabilities(
         <<code::8, length::8, value::binary()-size(length), rest::binary()>>,
         capabilities,
         options
       ) do
    with {:ok, module} <- module_for_type(code),
         do: decode_capabilities(rest, [module.decode(value, options) | capabilities], options)
  end

  @impl Encoder
  def encode(%__MODULE__{capabilities: capabilities}, options) do
    Enum.map(capabilities, fn %module{} = capability ->
      data = module.encode(capability, options)
      length = IO.iodata_length(data)
      type = type_for_module(module)
      [<<type::8>>, <<length::8>>, data]
    end)
  end

  @attributes [
    {MultiProtocol, 1},
    {RouteRefresh, 2},
    {ExtendedMessage, 6},
    {GracefulRestart, 64},
    {FourOctetsASN, 65},
    {EnanchedRouteRefresh, 70}
  ]

  for {module, code} <- @attributes do
    defp type_for_module(unquote(module)), do: unquote(code)
  end

  defp type_for_module(module), do: raise("Unknown path attribute module #{module}")

  for {module, code} <- @attributes do
    defp module_for_type(unquote(code)), do: {:ok, unquote(module)}
  end

  defp module_for_type(_code), do: {:error, %Encoder.Error{code: :open_message}}
end
