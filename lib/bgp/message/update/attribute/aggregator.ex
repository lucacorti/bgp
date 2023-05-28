defmodule BGP.Message.UPDATE.Attribute.Aggregator do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.{FSM, Message, Message.Encoder, Message.NOTIFICATION}

  @asn_max :math.pow(2, 16) - 1
  @asn_four_octets_max :math.pow(2, 32) - 1

  @type t :: %__MODULE__{asn: BGP.asn(), address: IP.Address.t()}

  @enforce_keys [:asn, :address]
  defstruct asn: nil, address: nil

  @behaviour Encoder

  @impl Encoder
  def decode(<<asn::32, address::binary-size(4)>>, %FSM{four_octets: true} = fsm)
      when asn > 0 and asn < @asn_four_octets_max do
    case Message.decode_address(address) do
      {:ok, address} ->
        {%__MODULE__{asn: asn, address: address}, fsm}

      {:error, data} ->
        raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list, data: data
    end
  end

  def decode(<<asn::16, prefix::binary-size(4)>>, %FSM{four_octets: false} = fsm)
      when asn > 0 and asn < @asn_max do
    case Message.decode_address(prefix) do
      {:ok, address} ->
        {%__MODULE__{asn: asn, address: address}, fsm}

      {:error, data} ->
        raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list, data: data
    end
  end

  def decode(data, _fsm) do
    raise NOTIFICATION, code: :update_message, subcode: :attribute_length_error, data: data
  end

  @impl Encoder
  def encode(%__MODULE__{asn: asn, address: address}, %FSM{} = fsm) do
    asn_length = if fsm.four_octets, do: 32, else: 16
    {address, _size} = Message.encode_address(address)
    {[<<asn::size(asn_length)>>, address], div(asn_length, 8) + 4, fsm}
  end
end
