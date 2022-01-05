defmodule BGP.Message.Update.Attribute.AS4Aggregator do
  @moduledoc false

  alias BGP.Message.Encoder
  alias BGP.Prefix

  @type t :: %__MODULE__{asn: BGP.asn(), address: Prefix.t()}

  @enforce_keys [:asn, :address]
  defstruct asn: nil, address: nil

  @behaviour Encoder

  @impl Encoder
  def decode(<<asn::32, prefix::binary()-size(4)>>, _options),
    do: {:ok, %__MODULE__{asn: asn, address: Prefix.decode(prefix)}}

  def decode(_data), do: :error

  @impl Encoder
  def encode(%__MODULE__{asn: asn, address: address}, _options) do
    with {:ok, prefix, 32 = _length} <- Prefix.encode(address),
         do: <<asn::32, prefix::binary()-size(4)>>
  end

  def encode(_origin, _options), do: :error
end
