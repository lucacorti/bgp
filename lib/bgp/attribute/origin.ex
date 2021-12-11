defmodule BGP.Attribute.Origin do
  @type origin :: :igp | :egp | :incomplete
  @type t :: %__MODULE__{origin: origin()}

  @enforce_keys [:origin]
  defstruct origin: nil

  alias BGP.Attribute

  @behaviour Attribute

  @impl Attribute
  def decode(<<0::8>>), do: {:ok, %__MODULE__{origin: :igp}}
  def decode(<<1::8>>), do: {:ok, %__MODULE__{origin: :egp}}
  def decode(<<2::8>>), do: {:ok, %__MODULE__{origin: :incomplete}}
  def decode(<<_origin::8>>), do: :error

  @impl Attribute
  def encode(%__MODULE__{origin: :igp}), do: <<0::8>>
  def encode(%__MODULE__{origin: :egp}), do: <<1::8>>
  def encode(%__MODULE__{origin: :incomplete}), do: <<2::8>>
  def encode(_origin), do: :error
end
