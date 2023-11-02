defmodule BGP.Message.UPDATE.Attribute.NextHop do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  @type t :: %__MODULE__{value: IP.Address.t()}

  @enforce_keys [:value]
  defstruct value: nil

  alias BGP.{Message, Message.Encoder, Message.NOTIFICATION}

  @behaviour Encoder

  @impl Encoder
  def decode(address, session) do
    case Message.decode_address(address) do
      {:ok, address} ->
        {%__MODULE__{value: address}, session}

      {:error, data} ->
        raise NOTIFICATION, code: :update_message, subcode: :invalid_nexthop_attribute, data: data
    end
  end

  @impl Encoder
  def encode(%__MODULE__{value: value}, session) do
    {encoded, 32} = Message.encode_address(value)
    {encoded, 4, session}
  end
end
