defmodule BGP.Message.RouteRefresh do
  @moduledoc false

  alias BGP.AFN

  @type t :: %__MODULE__{afi: AFN.afi(), safi: AFN.safi()}
  @enforce_keys [:afi, :safi]
  defstruct afi: nil, safi: nil

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(<<afi::16, _reserved::8, safi::8>>, _options),
    do: {:ok, %__MODULE__{afi: AFN.decode_afi(afi), safi: AFN.decode_safi(safi)}}

  @impl Encoder
  def encode(%__MODULE__{afi: afi, safi: safi}, _options),
    do: [<<AFN.encode_afi(afi)::16, 0::8, AFN.encode_safi(safi)::8>>]
end
