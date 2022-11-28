defmodule BGP.Message.UPDATE.Attribute.AS4Aggregator do
  @moduledoc false

  alias BGP.Message.{Encoder, NOTIFICATION}
  alias BGP.Prefix

  @type t :: %__MODULE__{asn: BGP.asn(), address: Prefix.t()}

  @enforce_keys [:asn, :address]
  defstruct asn: nil, address: nil

  @behaviour Encoder

  @impl Encoder
  def decode(<<asn::32, prefix::binary-size(4)>>, _options),
    do: %__MODULE__{asn: asn, address: Prefix.decode(prefix)}

  def decode(_data) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end

  @impl Encoder
  def encode(%__MODULE__{asn: asn, address: address}, _options) do
    with {:ok, prefix, 32 = _length} <- Prefix.encode(address),
         do: <<asn::32, prefix::binary-size(4)>>
  end

  def encode(_origin, _options) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end
end
