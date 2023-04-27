defmodule BGP.Message.UPDATE.Attribute.Origin do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.Message.{Encoder, NOTIFICATION}

  @type origin :: :igp | :egp | :incomplete
  @type t :: %__MODULE__{origin: origin()}

  @enforce_keys [:origin]
  defstruct origin: nil

  @behaviour Encoder

  @impl Encoder
  def decode(data, fsm), do: {%__MODULE__{origin: decode_origin(data)}, fsm}

  def decode_origin(<<0::8>>), do: :igp
  def decode_origin(<<1::8>>), do: :egp
  def decode_origin(<<2::8>>), do: :incomplete

  def decode_origin(_data) do
    raise NOTIFICATION, code: :update_message, subcode: :invalid_origin_attribute
  end

  @impl Encoder
  def encode(%__MODULE__{origin: origin}, fsm), do: {encode_origin(origin), 1, fsm}

  defp encode_origin(:igp), do: <<0::8>>
  defp encode_origin(:egp), do: <<1::8>>
  defp encode_origin(:incomplete), do: <<2::8>>
end
