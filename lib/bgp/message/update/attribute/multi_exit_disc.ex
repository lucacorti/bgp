defmodule BGP.Message.UPDATE.Attribute.MultiExitDisc do
  @moduledoc false

  alias BGP.Message.{Encoder, NOTIFICATION}

  @type t :: %__MODULE__{value: non_neg_integer()}

  @enforce_keys [:value]
  defstruct value: nil

  @behaviour Encoder

  @impl Encoder
  def decode(<<multi_exit_disc::32>>, _fsm), do: %__MODULE__{value: multi_exit_disc}

  def decode(_data) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end

  @impl Encoder
  def encode(%__MODULE__{value: multi_exit_disc}, _fsm), do: <<multi_exit_disc::32>>

  def encode(_origin) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end
end
