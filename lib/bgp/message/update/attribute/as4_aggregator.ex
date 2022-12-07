defmodule BGP.Message.UPDATE.Attribute.AS4Aggregator do
  @moduledoc false

  alias BGP.Message.{Encoder, NOTIFICATION}

  @type t :: %__MODULE__{asn: BGP.asn(), address: IP.Address.t()}

  @enforce_keys [:asn, :address]
  defstruct asn: nil, address: nil

  @behaviour Encoder

  @impl Encoder
  def decode(<<asn::32, prefix::binary-size(4)>>, _fsm) do
    case IP.Address.from_binary(prefix) do
      {:ok, address} ->
        %__MODULE__{asn: asn, address: address}

      {:error, _reason} ->
        raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
    end
  end

  def decode(_data) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end

  @impl Encoder
  def encode(%__MODULE__{asn: asn, address: address}, _fsm) do
    prefix = IP.Address.to_integer(address)
    [<<asn::32>>, <<prefix::32>>]
  end

  def encode(_origin, _fsm) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end
end
