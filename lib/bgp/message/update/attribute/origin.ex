defmodule BGP.Message.UPDATE.Attribute.Origin do
  @moduledoc false

  @type origin :: :igp | :egp | :incomplete
  @type t :: %__MODULE__{origin: origin()}

  @enforce_keys [:origin]
  defstruct origin: nil

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(<<0::8>>, _options), do: {:ok, %__MODULE__{origin: :igp}}
  def decode(<<1::8>>, _options), do: {:ok, %__MODULE__{origin: :egp}}
  def decode(<<2::8>>, _options), do: {:ok, %__MODULE__{origin: :incomplete}}
  def decode(_data, _options), do: :error

  @impl Encoder
  def encode(%__MODULE__{origin: :igp}, _options), do: <<0::8>>
  def encode(%__MODULE__{origin: :egp}, _options), do: <<1::8>>
  def encode(%__MODULE__{origin: :incomplete}, _options), do: <<2::8>>
  def encode(_origin, _options), do: :error
end
