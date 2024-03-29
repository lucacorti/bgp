defmodule BGP.Message.UPDATE.Attribute.MpReachNLRI do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.Message
  alias BGP.Message.{AFN, NOTIFICATION}

  @type t :: %__MODULE__{
          afi: AFN.afi(),
          safi: AFN.safi(),
          next_hop: IP.Address.t(),
          nlri: [IP.Prefix.t()]
        }

  defstruct afi: nil, safi: nil, next_hop: nil, nlri: []

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(
        <<afi::16, safi::8, length::8, next_hop::binary-unit(1)-size(length), _::8,
          nlri::binary>>,
        session
      ) do
    address =
      case Message.decode_address(next_hop) do
        {:ok, address} ->
          address

        {:error, data} ->
          raise NOTIFICATION,
            code: :update_message,
            subcode: :invalid_nexthop_attribute,
            data: data
      end

    nlri_prefixes =
      case Message.decode_prefixes(nlri) do
        {:ok, nlri_prefixes} ->
          nlri_prefixes

        {:error, data} ->
          raise NOTIFICATION, code: :update_message, data: data
      end

    {
      %__MODULE__{
        afi: decode_afi(afi),
        safi: decode_safi(safi),
        next_hop: address,
        nlri: nlri_prefixes
      },
      session
    }
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
    {next_hop, next_hop_length} = Message.encode_address(message.next_hop)
    {nlri, nlri_length} = Message.encode_prefixes(message.nlri)

    {
      [
        <<encode_afi(message.afi)::16>>,
        <<encode_safi(message.safi)::8>>,
        <<next_hop_length::8>>,
        next_hop,
        <<0::8>>,
        nlri
      ],
      4 + div(next_hop_length, 8) + 1 + nlri_length,
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
