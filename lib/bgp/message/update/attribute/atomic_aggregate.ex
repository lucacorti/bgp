defmodule BGP.Message.UPDATE.Attribute.AtomicAggregate do
  @moduledoc false

  @type t :: %__MODULE__{}
  defstruct []

  alias BGP.Message.{Encoder, NOTIFICATION}

  @behaviour Encoder

  @impl Encoder
  def decode(<<>>, _fsm), do: %__MODULE__{}

  def decode(data, _fsm) do
    raise NOTIFICATION, code: :update_message, subcode: :attribute_length_error, data: data
  end

  @impl Encoder
  def encode(%__MODULE__{}, _fsm), do: {<<>>, 0}
end
