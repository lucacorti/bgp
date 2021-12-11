defmodule BGP.Attribute.LocalPref do
  @type t :: %__MODULE__{value: non_neg_integer()}

  @enforce_keys [:value]
  defstruct value: nil

  alias BGP.Attribute

  @behaviour Attribute

  @impl Attribute
  def decode(<<local_pref::32>>), do: {:ok, %__MODULE__{value: local_pref}}

  @impl Attribute
  def encode(%__MODULE__{value: local_pref}), do: <<local_pref::32>>

  def encode(_origin), do: :error
end
