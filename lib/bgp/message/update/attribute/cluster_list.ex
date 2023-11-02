defmodule BGP.Message.UPDATE.Attribute.ClusterList do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  @type t :: %__MODULE__{value: [IP.Address.t()]}

  @enforce_keys [:value]
  defstruct value: nil

  alias BGP.{Message, Message.Encoder, Message.NOTIFICATION}

  @behaviour Encoder

  @impl Encoder
  def decode(data, session), do: {%__MODULE__{value: decode_cluster_ids(data, [])}, session}

  defp decode_cluster_ids(<<>>, cluster_ids), do: Enum.reverse(cluster_ids)

  defp decode_cluster_ids(<<address::binary-size(4), rest::binary>>, cluster_ids) do
    case Message.decode_address(address) do
      {:ok, address} ->
        decode_cluster_ids(rest, [address | cluster_ids])

      {:error, data} ->
        raise NOTIFICATION, code: :update_message, subcode: :invalid_nexthop_attribute, data: data
    end
  end

  @impl Encoder
  def encode(%__MODULE__{value: value}, session) do
    {data, length} =
      Enum.map_reduce(value, 0, fn address, length ->
        {encoded, 32} = Message.encode_address(address)
        {encoded, length + 4}
      end)

    {data, length, session}
  end
end
