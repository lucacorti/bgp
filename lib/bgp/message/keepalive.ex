defmodule BGP.Message.KEEPALIVE do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.Message.{Encoder, NOTIFICATION}

  @type t :: %__MODULE__{}
  defstruct []

  @behaviour Encoder

  @impl Encoder
  def decode(<<>>, session), do: {%__MODULE__{}, session}

  def decode(_keepalive, _session) do
    raise NOTIFICATION, code: :message_header, subcode: :bad_message_length
  end

  @impl Encoder
  def encode(_keepalive, session), do: {<<>>, 0, session}
end
