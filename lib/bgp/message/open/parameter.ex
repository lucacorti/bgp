defmodule BGP.Message.OPEN.Parameter do
  @moduledoc false

  alias BGP.Message.Encoder
  alias BGP.Message.OPEN.Parameter.Capabilities

  @type t :: struct()

  @behaviour Encoder

  @impl Encoder
  def decode(<<type::8, length::8, data::binary()-size(length)>>, options) do
    with {:ok, module} <- module_for_type(type),
         do: module.decode(data, options)
  end

  @impl Encoder
  def encode(%module{} = message, options) do
    data = module.encode(message, options)

    [<<type_for_module(module)::8>>, <<IO.iodata_length(data)::8>>, data]
  end

  attributes = [
    {Capabilities, 2}
  ]

  for {module, code} <- attributes do
    defp type_for_module(unquote(module)), do: unquote(code)
  end

  defp type_for_module(module), do: raise("Unknown path attribute module #{module}")

  for {module, code} <- attributes do
    defp module_for_type(unquote(code)), do: {:ok, unquote(module)}
  end

  defp module_for_type(_code),
    do: {:error, %Encoder.Error{code: :open_message, subcode: :unsupported_optional_parameter}}
end
