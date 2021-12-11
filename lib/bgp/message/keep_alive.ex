defmodule BGP.Message.KeepAlive do
  defstruct data: ""

  alias BGP.Message

  @behaviour Message

  @impl Message
  def decode(_data, _length), do: {:ok, %__MODULE__{}}

  @impl Message
  def encode(_msg), do: <<>>
end
