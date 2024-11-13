defmodule BGP.Message.UPDATE.Attribute.Origin do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.Message.{Encoder, NOTIFICATION}

  @type t :: %__MODULE__{value: non_neg_integer()}

  @enforce_keys [:value]
  defstruct value: nil

  @behaviour Encoder

  @impl Encoder
  def decode(<<value::8>>, session) when value in 0..2, do: {%__MODULE__{value: value}, session}

  def decode(_data, _session) do
    raise NOTIFICATION, code: :update_message, subcode: :invalid_origin_attribute
  end

  @impl Encoder
  def encode(%__MODULE__{value: value}, session) when value in 0..2,
    do: {<<value::8>>, 1, session}

  def encode(_data, _session) do
    raise NOTIFICATION, code: :update_message, subcode: :invalid_origin_attribute
  end
end
