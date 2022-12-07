defmodule BGP.Message.UPDATE.Attribute.NextHop do
  @moduledoc false

  alias BGP.Message.NOTIFICATION
  alias BGP.Prefix

  @type t :: %__MODULE__{value: Prefix.t()}

  @enforce_keys [:value]
  defstruct value: nil

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(data, _fsm) do
    case Prefix.decode(data) do
      {:ok, prefix} ->
        %__MODULE__{value: prefix}

      :error ->
        raise NOTIFICATION, code: :update_message, subcode: :invalid_nexthop_attribute
    end
  end

  @impl Encoder
  def encode(%__MODULE__{value: value}, _fsm) do
    case Prefix.encode(value) do
      {:ok, prefix, 32} ->
        [<<32::8>>, prefix]

      :error ->
        raise NOTIFICATION, code: :update_message, subcode: :invalid_nexthop_attribute
    end
  end
end
