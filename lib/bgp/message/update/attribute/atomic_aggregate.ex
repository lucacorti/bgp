defmodule BGP.Message.UPDATE.Attribute.AtomicAggregate do
  @moduledoc false

  @type t :: %__MODULE__{}
  defstruct []

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(_data, _fsm), do: %__MODULE__{}

  @impl Encoder
  def encode(%__MODULE__{}, _fsm), do: <<>>
end
