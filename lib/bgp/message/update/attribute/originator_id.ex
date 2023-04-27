defmodule BGP.Message.UPDATE.Attribute.OriginatorId do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.Message.NOTIFICATION

  @type t :: %__MODULE__{value: IP.Address.t()}

  @enforce_keys [:value]
  defstruct value: nil

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(address, fsm) do
    case IP.Address.from_binary(address) do
      {:ok, prefix} ->
        {%__MODULE__{value: prefix}, fsm}

      {:error, _reason} ->
        raise NOTIFICATION, code: :update_message, subcode: :invalid_nexthop_attribute
    end
  end

  @impl Encoder
  def encode(%__MODULE__{value: value}, fsm) do
    {[<<32::8>>, <<IP.Address.to_integer(value)::32>>], 5, fsm}
  end
end
