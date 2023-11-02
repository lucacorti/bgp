defmodule BGP.Message.UPDATE.Attribute.AtomicAggregate do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  @type t :: %__MODULE__{}
  defstruct []

  alias BGP.Message.{Encoder, NOTIFICATION}

  @behaviour Encoder

  @impl Encoder
  def decode(<<>>, session), do: {%__MODULE__{}, session}

  def decode(data, _session) do
    raise NOTIFICATION, code: :update_message, subcode: :attribute_length_error, data: data
  end

  @impl Encoder
  def encode(%__MODULE__{}, session), do: {<<>>, 0, session}
end
