defmodule BGP.Message.UPDATE.Attribute.AS4Aggregator do
  @moduledoc false

  alias BGP.Message.{Encoder, NOTIFICATION}
  alias BGP.Prefix

  @type t :: %__MODULE__{asn: BGP.asn(), address: Prefix.t()}

  @enforce_keys [:asn, :address]
  defstruct asn: nil, address: nil

  @behaviour Encoder

  @impl Encoder
  def decode(<<asn::32, prefix::binary-size(4)>>, _fsm) do
    case Prefix.decode(prefix) do
      {:ok, address} ->
        %__MODULE__{asn: asn, address: address}

      :error ->
        raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
    end
  end

  def decode(_data) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end

  @impl Encoder
  def encode(%__MODULE__{asn: asn, address: address}, _fsm) do
    case Prefix.encode(address) do
      {:ok, prefix, 32} ->
        <<asn::32, prefix::binary-size(4)>>

      :error ->
        raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
    end
  end

  def encode(_origin, _fsm) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end
end
