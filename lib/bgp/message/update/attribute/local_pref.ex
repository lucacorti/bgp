defmodule BGP.Message.Update.Attribute.LocalPref do
  @moduledoc false

  @type t :: %__MODULE__{value: non_neg_integer()}

  @enforce_keys [:value]
  defstruct value: nil

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(<<local_pref::32>>), do: {:ok, %__MODULE__{value: local_pref}}

  def decode(_data), do: :error

  @impl Encoder
  def encode(%__MODULE__{value: local_pref}), do: <<local_pref::32>>

  def encode(_origin), do: :error
end
