defmodule BGP.Message.UPDATE.Attribute.AS4Aggregator do
  @moduledoc false

  alias BGP.Message.{Encoder, NOTIFICATION}

  @asn_four_octets_max :math.pow(2, 32) - 1

  @type t :: %__MODULE__{asn: BGP.asn(), address: IP.Address.t()}

  @enforce_keys [:asn, :address]
  defstruct asn: nil, address: nil

  @behaviour Encoder

  @impl Encoder
  def decode(<<asn::32, prefix::binary-size(4)>>, fsm)
      when asn > 0 and asn < @asn_four_octets_max do
    case IP.Address.from_binary(prefix) do
      {:ok, address} ->
        {%__MODULE__{asn: asn, address: address}, fsm}

      {:error, _reason} ->
        raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
    end
  end

  def decode(data, _fsm) do
    raise NOTIFICATION, code: :update_message, subcode: :attribute_length_error, data: data
  end

  @impl Encoder
  def encode(%__MODULE__{asn: asn, address: address}, fsm) do
    prefix = IP.Address.to_integer(address)

    {
      [<<asn::32>>, <<prefix::32>>],
      8,
      fsm
    }
  end
end
