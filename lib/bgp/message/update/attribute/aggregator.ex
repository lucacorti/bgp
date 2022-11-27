defmodule BGP.Message.UPDATE.Attribute.Aggregator do
  @moduledoc false

  alias BGP.Message.Encoder
  alias BGP.Prefix

  @asn_max :math.pow(2, 16) - 1
  @asn_four_octets_max :math.pow(2, 16) - 1

  @type t :: %__MODULE__{asn: BGP.asn(), address: Prefix.t()}

  @enforce_keys [:asn, :address]
  defstruct asn: nil, address: nil

  @behaviour Encoder

  @impl Encoder
  def decode(aggregator, options) do
    four_octets = Keyword.get(options, :four_octets, false)
    decode_aggregator(aggregator, four_octets)
  end

  def decode_aggregator(<<asn::32, prefix::binary-size(4)>>, true = _four_octets)
      when asn > 0 and asn < @asn_four_octets_max,
      do: {:ok, %__MODULE__{asn: asn, address: Prefix.decode(prefix)}}

  def decode_aggregator(<<asn::16, prefix::binary-size(4)>>, false = _four_octets)
      when asn > 0 and asn < @asn_max,
      do: {:ok, %__MODULE__{asn: asn, address: Prefix.decode(prefix)}}

  def decode_aggregator(_aggregator, _four_octets),
    do: :skip

  @impl Encoder
  def encode(%__MODULE__{asn: asn, address: address}, options) do
    as_length =
      Enum.find_value(options, 16, fn
        {:four_octets, true} -> 32
        _ -> nil
      end)

    with {:ok, prefix, 32 = _length} <- Prefix.encode(address),
         do: <<asn::integer-size(as_length), prefix::binary-size(4)>>
  end

  def encode(_origin, _options), do: :error
end
