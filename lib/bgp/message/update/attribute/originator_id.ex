defmodule BGP.Message.UPDATE.Attribute.OriginatorId do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  @type t :: %__MODULE__{value: IP.Address.t()}

  @enforce_keys [:value]
  defstruct value: nil

  alias BGP.{Message, Message.Encoder, Message.NOTIFICATION}

  @behaviour Encoder

  @impl Encoder
  def decode(address, fsm) do
    case Message.decode_address(address) do
      {:ok, address} ->
        {%__MODULE__{value: address}, fsm}

      {:error, data} ->
        raise NOTIFICATION, code: :update_message, subcode: :invalid_nexthop_attribute, data: data
    end
  end

  @impl Encoder
  def encode(%__MODULE__{value: value}, fsm) do
    {address, size} = Message.encode_address(value)
    {[<<size::8>>, address], div(size, 8) + 1, fsm}
  end
end
