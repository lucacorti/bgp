defmodule BGP.Message.UPDATE.Attribute.Aggregator do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.Message
  alias BGP.Message.{Encoder, NOTIFICATION, OPEN}
  alias BGP.Server.Session

  @asn_max :math.pow(2, 16) - 1
  @asn_four_octets_max :math.pow(2, 32) - 1

  @type t :: %__MODULE__{asn: OPEN.asn(), address: IP.Address.t()}

  @enforce_keys [:asn, :address]
  defstruct asn: nil, address: nil

  @behaviour Encoder

  @impl Encoder
  def decode(<<asn::32, address::binary-size(4)>>, %Session{four_octets: true} = session)
      when asn > 0 and asn < @asn_four_octets_max do
    case Message.decode_address(address) do
      {:ok, address} ->
        {%__MODULE__{asn: asn, address: address}, session}

      {:error, data} ->
        raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list, data: data
    end
  end

  def decode(<<asn::16, prefix::binary-size(4)>>, %Session{four_octets: false} = session)
      when asn > 0 and asn < @asn_max do
    case Message.decode_address(prefix) do
      {:ok, address} ->
        {%__MODULE__{asn: asn, address: address}, session}

      {:error, data} ->
        raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list, data: data
    end
  end

  def decode(data, _session) do
    raise NOTIFICATION, code: :update_message, subcode: :attribute_length_error, data: data
  end

  @impl Encoder
  def encode(%__MODULE__{asn: asn, address: address}, %Session{four_octets: true} = session) do
    {address, 32} = Message.encode_address(address)
    {[<<asn::32>>, address], 8, session}
  end

  def encode(%__MODULE__{asn: asn, address: address}, session) do
    {address, 32} = Message.encode_address(address)
    {[<<asn::16>>, address], 6, session}
  end
end
