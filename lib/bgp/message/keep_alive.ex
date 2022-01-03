defmodule BGP.Message.KeepAlive do
  @moduledoc false

  defstruct []

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(_data, _options), do: {:ok, %__MODULE__{}}

  @impl Encoder
  def encode(_msg, _options), do: <<>>
end
