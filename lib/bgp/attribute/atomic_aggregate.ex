defmodule BGP.Attribute.AtomicAggregate do
  @type t :: %__MODULE__{}
  defstruct []

  alias BGP.Attribute

  @behaviour Attribute

  @impl Attribute
  def decode(_data), do: {:ok, %__MODULE__{}}

  @impl Attribute
  def encode(%__MODULE__{}), do: <<>>
  def encode(_origin), do: :error
end
