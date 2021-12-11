defmodule BGP.Attribute.Aggregator do
  alias BGP.{Attribute, Prefix}

  @type asn :: non_neg_integer()
  @type t :: %__MODULE__{asn: asn(), address: Prefix.t()}

  @enforce_keys [:asn, :address]
  defstruct asn: nil, address: nil

  @behaviour Attribute

  @impl Attribute
  def decode(<<asn::16, prefix::binary-size(32)>>),
    do: {:ok, %__MODULE__{asn: asn, address: Prefix.decode(prefix)}}

  @impl Attribute
  def encode(%__MODULE__{asn: asn, address: address}) do
    {prefix, length} = Prefix.encode(address)
    <<asn::16, prefix::binary-size(length)>>
  end

  def encode(_origin), do: :error
end
