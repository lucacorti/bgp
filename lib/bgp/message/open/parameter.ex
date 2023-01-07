defmodule BGP.Message.OPEN.Parameter do
  @moduledoc false

  alias BGP.FSM
  alias BGP.Message.Encoder
  alias BGP.Message.{NOTIFICATION, OPEN.Parameter.Capabilities}

  @type t :: struct()

  @behaviour Encoder

  @impl Encoder
  def decode(
        <<type::8, length::16, data::binary-size(length)>>,
        %FSM{extended_optional_parameters: true} = fsm
      ) do
    module_for_type(type).decode(data, fsm)
  end

  def decode(<<type::8, length::8, data::binary-size(length)>>, fsm) do
    module_for_type(type).decode(data, fsm)
  end

  @impl Encoder
  def encode(%module{} = message, %FSM{extended_optional_parameters: true} = fsm) do
    {data, length, fsm} = module.encode(message, fsm)

    {
      [<<type_for_module(module)::8>>, <<length::16>>, data],
      3 + length,
      fsm
    }
  end

  def encode(%module{} = message, fsm) do
    {data, length, fsm} = module.encode(message, fsm)

    {
      [<<type_for_module(module)::8>>, <<length::8>>, data],
      2 + length,
      fsm
    }
  end

  attributes = [
    {Capabilities, 2}
  ]

  for {module, code} <- attributes do
    defp type_for_module(unquote(module)), do: unquote(code)
  end

  for {module, code} <- attributes do
    defp module_for_type(unquote(code)), do: unquote(module)
  end

  defp module_for_type(_code) do
    raise NOTIFICATION, code: :open_message, subcode: :unsupported_optional_parameter
  end
end
