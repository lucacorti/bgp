defmodule BGP.Message.UPDATE.Attribute.Origin do
  @moduledoc false

  alias BGP.Message.{Encoder, NOTIFICATION}

  @type origin :: :igp | :egp | :incomplete
  @type t :: %__MODULE__{origin: origin()}

  @enforce_keys [:origin]
  defstruct origin: nil

  @behaviour Encoder

  @impl Encoder
  def decode(<<0::8>>, _fsm), do: %__MODULE__{origin: :igp}
  def decode(<<1::8>>, _fsm), do: %__MODULE__{origin: :egp}
  def decode(<<2::8>>, _fsm), do: %__MODULE__{origin: :incomplete}

  def decode(_data, _fsm) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end

  @impl Encoder
  def encode(%__MODULE__{origin: :igp}, _fsm), do: <<0::8>>
  def encode(%__MODULE__{origin: :egp}, _fsm), do: <<1::8>>
  def encode(%__MODULE__{origin: :incomplete}, _fsm), do: <<2::8>>

  def encode(_origin, _fsm) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end
end
