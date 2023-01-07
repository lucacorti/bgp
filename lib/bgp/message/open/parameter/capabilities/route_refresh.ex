defmodule BGP.Message.OPEN.Parameter.Capabilities.RouteRefresh do
  @moduledoc false

  @type t :: %__MODULE__{}
  defstruct []

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(<<>>, fsm), do: {%__MODULE__{}, fsm}

  @impl Encoder
  def encode(_multi_protocol, fsm), do: {<<>>, 0, fsm}
end
