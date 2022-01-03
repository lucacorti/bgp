defmodule BGP.Message.Update.Attribute.NextHop do
  @moduledoc false

  alias BGP.Prefix

  @type t :: %__MODULE__{value: Prefix.t()}

  @enforce_keys [:value]
  defstruct value: nil

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(data, _options) do
    with {:ok, prefix} <- Prefix.decode(data),
         do: {:ok, %__MODULE__{value: prefix}}
  end

  @impl Encoder
  def encode(%__MODULE__{value: value}, _options) do
    with {:ok, prefix, length} <- Prefix.encode(value),
         do: [<<length::8>>, prefix]
  end
end
