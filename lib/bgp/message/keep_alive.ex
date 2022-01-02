defmodule BGP.Message.KeepAlive do
  @moduledoc false

  defstruct []

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(_data), do: {:ok, %__MODULE__{}}

  @impl Encoder
  def encode(_msg), do: <<>>
end
