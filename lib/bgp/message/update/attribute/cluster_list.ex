defmodule BGP.Message.UPDATE.Attribute.ClusterList do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  @type t :: %__MODULE__{values: [IP.Address.t()]}

  @enforce_keys [:values]
  defstruct values: nil

  alias BGP.{Message, Message.Encoder, Message.NOTIFICATION}

  @behaviour Encoder

  @impl Encoder
  def decode(data, fsm), do: {%__MODULE__{values: decode_cluster_ids(data, [])}, fsm}

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
  def encode(%__MODULE__{values: values}, fsm) do
    {data, length} =
      Enum.map_reduce(values, 0, fn address, length ->
        {<<IP.Address.to_integer(address)::unit(32)-size(1)>>, length + 4}
      end)

    {data, length, fsm}
  end
end
