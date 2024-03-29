defmodule BGP.Message.ROUTEREFRESH do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.Message.{AFN, Encoder, NOTIFICATION}

  @type subtype :: :route_refresh | :borr | :eorr
  @type t :: %__MODULE__{afi: AFN.afi(), safi: AFN.safi()}
  @enforce_keys [:afi, :safi]
  defstruct afi: nil, safi: nil, subtype: :route_refresh

  @behaviour Encoder

  @impl Encoder
  def decode(<<afi::16, subtype::8, safi::8>>, session) do
    {
      %__MODULE__{
        afi: decode_afi(afi),
        safi: decode_safi(safi),
        subtype: decode_subtype(subtype)
      },
      session
    }
  end

  defp decode_afi(afi) do
    case AFN.decode_afi(afi) do
      {:ok, afi} -> afi
      :error -> raise NOTIFICATION, code: :route_refresh_message
    end
  end

  defp decode_safi(safi) do
    case AFN.decode_safi(safi) do
      {:ok, safi} -> safi
      :error -> raise NOTIFICATION, code: :route_refresh_message
    end
  end

  defp decode_subtype(0), do: :route_refresh
  defp decode_subtype(1), do: :borr
  defp decode_subtype(2), do: :eorr

  defp decode_subtype(_code) do
    raise NOTIFICATION, code: :route_refresh_message
  end

  @impl Encoder
  def encode(%__MODULE__{afi: afi, safi: safi, subtype: subtype}, session) do
    {
      [<<encode_afi(afi)::16, encode_subtype(subtype)::8, encode_safi(safi)::8>>],
      4,
      session
    }
  end

  defp encode_afi(afi) do
    case AFN.encode_afi(afi) do
      {:ok, afi} -> afi
      :error -> raise NOTIFICATION, code: :route_refresh_message
    end
  end

  defp encode_safi(safi) do
    case AFN.encode_safi(safi) do
      {:ok, safi} -> safi
      :error -> raise NOTIFICATION, code: :route_refresh_message
    end
  end

  defp encode_subtype(:route_refresh), do: 0
  defp encode_subtype(:borr), do: 1
  defp encode_subtype(:eorr), do: 2
end
