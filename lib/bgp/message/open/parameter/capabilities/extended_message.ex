defmodule BGP.Message.OPEN.Parameter.Capabilities.ExtendedMessage do
  @moduledoc false

  alias BGP.FSM

  @type t :: %__MODULE__{}
  defstruct []

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(<<>>, fsm), do: {%__MODULE__{}, %FSM{fsm | extended_message: true}}

  @impl Encoder
  def encode(_extended_message, fsm), do: {<<>>, 0, fsm}
end
