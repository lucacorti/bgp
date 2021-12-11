defmodule BGP.Attribute.NextHop do
  alias BGP.Prefix

  @type t :: %__MODULE__{value: Prefix.t()}

  @enforce_keys [:value]
  defstruct value: nil

  alias BGP.Attribute

  @behaviour Attribute

  @impl Attribute
  def decode(data), do: {:ok, %__MODULE__{value: Prefix.decode(data)}}

  @impl Attribute
  def encode(%__MODULE__{value: value}) do
    with {prefix, _length} <- Prefix.encode(value), do: prefix
  end

  def encode(_origin), do: :error
end
