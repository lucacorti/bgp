defmodule BGP.Message.UPDATE.Attribute.MpUnreachNLRI do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

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
  def decode(<<afi::16, safi::8, withdrawn_routes::binary>>, session) do
    case Message.decode_prefixes(withdrawn_routes) do
      {:ok, withdrawn_prefixes} ->
        {
          %__MODULE__{
            afi: decode_afi(afi),
            safi: decode_safi(safi),
            withdrawn_routes: withdrawn_prefixes
          },
          session
        }

      {:error, data} ->
        raise NOTIFICATION, code: :update_message, data: data
    end
  end

  def decode(_data, _session) do
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
  def encode(%__MODULE__{} = message, session) do
    {withdrawn_routes, length} = Message.encode_prefixes(message.withdrawn_routes)

    {
      [
        <<encode_afi(message.afi)::16>>,
        <<encode_safi(message.safi)::8>>,
        withdrawn_routes
      ],
      3 + length,
      session
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
