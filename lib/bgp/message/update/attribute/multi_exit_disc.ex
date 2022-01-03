defmodule BGP.Message.Update.Attribute.MultiExitDisc do
  @moduledoc false

  @type t :: %__MODULE__{value: non_neg_integer()}

  @enforce_keys [:value]
  defstruct value: nil

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def(decode(<<multi_exit_disc::32>>, _options), do: {:ok, %__MODULE__{value: multi_exit_disc}})

  def decode(_data), do: :error

  @impl Encoder
  def encode(%__MODULE__{value: multi_exit_disc}, _options), do: <<multi_exit_disc::32>>

  def encode(_origin), do: :error
end
