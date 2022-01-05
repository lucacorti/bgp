defmodule BGP.Message.UPDATE.Attribute.LocalPref do
  @moduledoc false

  @type t :: %__MODULE__{value: non_neg_integer()}

  @enforce_keys [:value]
  defstruct value: nil

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(<<local_pref::32>>, _options), do: {:ok, %__MODULE__{value: local_pref}}

  def decode(_data, _options), do: :error

  @impl Encoder
  def encode(%__MODULE__{value: local_pref}, _options), do: <<local_pref::32>>

  def encode(_origin, _options), do: :error
end
