defmodule BGP.Message.ROUTEREFRESH do
  @moduledoc false

  alias BGP.AFN
  alias BGP.Message.Encoder
  alias BGP.Message.Encoder.Error

  @type subtype :: :route_refresh | :borr | :eorr
  @type t :: %__MODULE__{afi: AFN.afi(), safi: AFN.safi()}
  @enforce_keys [:afi, :safi]
  defstruct afi: nil, safi: nil, subtype: :route_refresh

  @behaviour Encoder

  @impl Encoder
  def decode(<<afi::16, subtype::8, safi::8>>, _options) do
    with {:ok, subtype} <- decode_subtype(subtype) do
      {:ok,
       %__MODULE__{
         afi: AFN.decode_afi(afi),
         safi: AFN.decode_safi(safi),
         subtype: decode_subtype(subtype)
       }}
    end
  end

  defp decode_subtype(0), do: {:ok, :route_refresh}
  defp decode_subtype(1), do: {:ok, :borr}
  defp decode_subtype(2), do: {:ok, :eorr}
  defp decode_subtype(_code), do: {:error, %Error{code: :route_refresh_message}}

  @impl Encoder
  def encode(%__MODULE__{afi: afi, safi: safi, subtype: subtype}, _options),
    do: [<<AFN.encode_afi(afi)::16, encode_subtype(subtype)::8, AFN.encode_safi(safi)::8>>]

  defp encode_subtype(:route_refresh), do: 0
  defp encode_subtype(:borr), do: 1
  defp encode_subtype(:eorr), do: 2
end
