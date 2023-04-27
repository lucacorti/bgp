defmodule BGP.Message.KEEPALIVE do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.Message.{Encoder, NOTIFICATION}

  @type t :: %__MODULE__{}
  defstruct []

  @behaviour Encoder

  @impl Encoder
  def decode(<<>>, fsm), do: {%__MODULE__{}, fsm}

  def decode(_keepalive, _fsm) do
    raise NOTIFICATION, code: :message_header, subcode: :bad_message_length
  end

  @impl Encoder
  def encode(_keepalive, fsm), do: {<<>>, 0, fsm}
end
