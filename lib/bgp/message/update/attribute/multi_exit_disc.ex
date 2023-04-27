defmodule BGP.Message.UPDATE.Attribute.MultiExitDisc do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.Message.{Encoder, NOTIFICATION}

  @type t :: %__MODULE__{value: non_neg_integer()}

  @enforce_keys [:value]
  defstruct value: nil

  @behaviour Encoder

  @impl Encoder
  def decode(<<multi_exit_disc::32>>, fsm), do: {%__MODULE__{value: multi_exit_disc}, fsm}

  def decode(_data) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end

  @impl Encoder
  def encode(%__MODULE__{value: multi_exit_disc}, fsm), do: {<<multi_exit_disc::32>>, 4, fsm}
end
