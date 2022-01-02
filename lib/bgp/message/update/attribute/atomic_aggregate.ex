defmodule BGP.Message.Update.Attribute.AtomicAggregate do
  @moduledoc false

  @type t :: %__MODULE__{}
  defstruct []

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(_data), do: {:ok, %__MODULE__{}}

  @impl Encoder
  def encode(%__MODULE__{}), do: <<>>
  def encode(_origin), do: :error
end
