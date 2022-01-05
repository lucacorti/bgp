defmodule BGP.Message.UPDATE.Attribute.AtomicAggregate do
  @moduledoc false

  @type t :: %__MODULE__{}
  defstruct []

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(_data, _options), do: {:ok, %__MODULE__{}}

  @impl Encoder
  def encode(%__MODULE__{}, _options), do: <<>>
  def encode(_origin, _options), do: :error
end
