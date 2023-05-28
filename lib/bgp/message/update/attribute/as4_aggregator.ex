defmodule BGP.Message.UPDATE.Attribute.AS4Aggregator do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.{Message, Message.Encoder, Message.NOTIFICATION}

  @asn_four_octets_max :math.pow(2, 32) - 1

  @type t :: %__MODULE__{asn: BGP.asn(), address: IP.Address.t()}

  @enforce_keys [:asn, :address]
  defstruct asn: nil, address: nil

  @behaviour Encoder

  @impl Encoder
  def decode(<<asn::32, address::binary-size(4)>>, fsm)
      when asn > 0 and asn < @asn_four_octets_max do
    case Message.decode_address(address) do
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
  def encode(%__MODULE__{asn: asn, address: address}, fsm) do
    {address, 32} = Message.encode_address(address)
    {[<<asn::32>>, address], 8, fsm}
  end
end
