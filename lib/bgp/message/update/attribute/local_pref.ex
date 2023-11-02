defmodule BGP.Message.UPDATE.Attribute.LocalPref do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.Message.{Encoder, NOTIFICATION}

  @type t :: %__MODULE__{value: non_neg_integer()}

  @enforce_keys [:value]
  defstruct value: nil

  @behaviour Encoder

  @impl Encoder
  def decode(<<local_pref::32>>, session), do: {%__MODULE__{value: local_pref}, session}

  def decode(_data, _session) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end

  @impl Encoder
  def encode(%__MODULE__{value: local_pref}, session), do: {<<local_pref::32>>, 4, session}
end
