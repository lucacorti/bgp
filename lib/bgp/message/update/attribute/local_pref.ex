defmodule BGP.Message.UPDATE.Attribute.LocalPref do
  @moduledoc false

  alias BGP.Message.{Encoder, NOTIFICATION}

  @type t :: %__MODULE__{value: non_neg_integer()}

  @enforce_keys [:value]
  defstruct value: nil

  @behaviour Encoder

  @impl Encoder
  def decode(<<local_pref::32>>, _options), do: %__MODULE__{value: local_pref}

  def decode(_data, _options) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end

  @impl Encoder
  def encode(%__MODULE__{value: local_pref}, _options), do: <<local_pref::32>>

  def encode(_origin, _options) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end
end
