defmodule BGP.Message.KEEPALIVE do
  @moduledoc false

  defstruct []

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(<<>>, _options), do: {:ok, %__MODULE__{}}

  def decode(_keepalive, _options),
    do: {:error, %Encoder.Error{code: :message_header, subcode: :bad_message_length}}

  @impl Encoder
  def encode(_keepalive, _options), do: <<>>
end
