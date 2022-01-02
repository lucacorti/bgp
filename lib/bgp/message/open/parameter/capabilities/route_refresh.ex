defmodule BGP.Message.Open.Parameter.Capabilities.RouteRefresh do
  @moduledoc false

  @type t :: %__MODULE__{}
  defstruct []

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(<<>>), do: {:ok, %__MODULE__{}}

  @impl Encoder
  def encode(_multi_protocol), do: []
end
