defmodule BGP.Message.OPEN.Parameter.Capabilities.MultiProtocol do
  @moduledoc false

  alias BGP.Message.{AFN, Encoder, NOTIFICATION}

  @type t :: %__MODULE__{afi: AFN.afi(), safi: AFN.safi()}
  @enforce_keys [:afi, :safi]
  defstruct afi: nil, safi: nil

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(<<afi::16, _reserved::8, safi::8>>, _fsm),
    do: %__MODULE__{afi: decode_afi(afi), safi: decode_safi(safi)}

  def decode(_data, _fsm) do
    raise NOTIFICATION, code: :open_message
  end

  defp decode_afi(afi) do
    case AFN.decode_afi(afi) do
      {:ok, afi} -> afi
      :error -> raise NOTIFICATION, code: :open_message
    end
  end

  defp decode_safi(safi) do
    case AFN.decode_safi(safi) do
      {:ok, safi} -> safi
      :error -> raise NOTIFICATION, code: :open_message
    end
  end

  @impl Encoder
  def encode(%__MODULE__{afi: afi, safi: safi}, _fsm) do
    {
      [<<encode_afi(afi)::16>>, <<0::8>>, <<encode_safi(safi)::8>>],
      4
    }
  end

  def encode(_data, _fsm) do
    raise NOTIFICATION, code: :open_message
  end

  defp encode_afi(afi) do
    case AFN.encode_afi(afi) do
      {:ok, afi} -> afi
      :error -> raise NOTIFICATION, code: :open_message
    end
  end

  defp encode_safi(safi) do
    case AFN.encode_safi(safi) do
      {:ok, safi} -> safi
      :error -> raise NOTIFICATION, code: :open_message
    end
  end
end
