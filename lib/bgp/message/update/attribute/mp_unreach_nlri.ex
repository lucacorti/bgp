defmodule Bgp.Message.Update.Attribute.MpUnreachNLRI do
  @moduledoc false

  alias BGP.Message
  alias BGP.Message.{AFN, NOTIFICATION}

  @type t :: %__MODULE__{
          afi: AFN.afi(),
          safi: AFN.safi(),
          withdrawn_routes: [IP.Prefix.t()]
        }

  defstruct afi: nil, safi: nil, withdrawn_routes: []

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(<<afi::16, safi::8, withdrawn_routes::binary>>, _fsm) do
    %__MODULE__{
      afi: decode_afi(afi),
      safi: decode_safi(safi),
      withdrawn_routes: Message.decode_prefixes(withdrawn_routes)
    }
  end

  def decode(_data, _fsm) do
    raise NOTIFICATION, code: :update_message
  end

  defp decode_afi(afi) do
    case AFN.decode_afi(afi) do
      {:ok, afi} -> afi
      :error -> raise NOTIFICATION, code: :update_message
    end
  end

  defp decode_safi(safi) do
    case AFN.decode_safi(safi) do
      {:ok, safi} -> safi
      :error -> raise NOTIFICATION, code: :update_message
    end
  end

  @impl Encoder
  def encode(%__MODULE__{} = message, _fsm) do
    {withdrawn_routes, length} = Message.encode_prefixes(message.withdrawn_routes)

    {
      [
        <<encode_afi(message.afi)::16>>,
        <<encode_safi(message.safi)::8>>,
        withdrawn_routes
      ],
      3 + length
    }
  end

  defp encode_afi(afi) do
    case AFN.encode_afi(afi) do
      {:ok, afi} -> afi
      :error -> raise NOTIFICATION, code: :update_message
    end
  end

  defp encode_safi(safi) do
    case AFN.encode_safi(safi) do
      {:ok, safi} -> safi
      :error -> raise NOTIFICATION, code: :update_message
    end
  end
end
