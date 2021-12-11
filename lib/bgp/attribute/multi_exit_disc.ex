defmodule BGP.Attribute.MultiExitDisc do
  @type t :: %__MODULE__{value: non_neg_integer()}

  @enforce_keys [:value]
  defstruct value: nil

  alias BGP.Attribute

  @behaviour Attribute

  @impl Attribute
  def decode(<<multi_exit_disc::32>>), do: {:ok, %__MODULE__{value: multi_exit_disc}}

  @impl Attribute
  def encode(%__MODULE__{value: multi_exit_disc}), do: <<multi_exit_disc::32>>

  def encode(_origin), do: :error
end
