defmodule BGP.Message.Open.Parameter.Capabilities.FourOctetsASN do
  @moduledoc false

  @type t :: %__MODULE__{asn: BGP.asn()}
  @enforce_keys [:asn]
  defstruct asn: nil

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(<<asn::32>>, _options), do: {:ok, %__MODULE__{asn: asn}}

  @impl Encoder
  def encode(%__MODULE__{asn: asn}, _options), do: [<<asn::32>>]
end
