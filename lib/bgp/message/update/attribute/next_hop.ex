defmodule BGP.Message.UPDATE.Attribute.NextHop do
  @moduledoc false

  alias BGP.Message.NOTIFICATION

  @type t :: %__MODULE__{value: IP.Address.t()}

  @enforce_keys [:value]
  defstruct value: nil

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(address, _fsm) do
    case IP.Address.from_binary(address) do
      {:ok, prefix} ->
        %__MODULE__{value: prefix}

      {:error, _reason} ->
        raise NOTIFICATION, code: :update_message, subcode: :invalid_nexthop_attribute
    end
  end

  @impl Encoder
  def encode(%__MODULE__{value: value}, _fsm) do
    prefix = IP.Address.to_integer(value)
    {[<<32::8>>, <<prefix::32>>], 5}
  end
end
