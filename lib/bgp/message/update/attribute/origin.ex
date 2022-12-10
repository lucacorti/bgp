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
    raise NOTIFICATION, code: :update_message, subcode: :invalid_origin_attribute
  end

  @impl Encoder
  def encode(%__MODULE__{origin: origin}, _fsm), do: {encode_origin(origin), 1}

  defp encode_origin(:igp), do: <<0::8>>
  defp encode_origin(:egp), do: <<1::8>>
  defp encode_origin(:incomplete), do: <<2::8>>
end
