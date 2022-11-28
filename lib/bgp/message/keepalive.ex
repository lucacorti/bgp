defmodule BGP.Message.KEEPALIVE do
  @moduledoc false

  alias BGP.Message.{Encoder, NOTIFICATION}

  @type t :: %__MODULE__{}
  defstruct []

  @behaviour Encoder

  @impl Encoder
  def decode(<<>>, _options), do: %__MODULE__{}

  def decode(_keepalive, _options) do
    raise NOTIFICATION, code: :message_header, subcode: :bad_message_length
  end

  @impl Encoder
  def encode(_keepalive, _options), do: <<>>
end
