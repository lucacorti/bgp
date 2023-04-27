defmodule BGP.Message.UPDATE.Attribute.ClusterList do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.Message.NOTIFICATION

  @type t :: %__MODULE__{values: [IP.Address.t()]}

  @enforce_keys [:values]
  defstruct values: nil

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(data, fsm), do: {%__MODULE__{values: decode_cluster_ids(data, [])}, fsm}

  defp decode_cluster_ids(<<>>, cluster_ids), do: Enum.reverse(cluster_ids)

  defp decode_cluster_ids(<<address::binary-size(4), rest::binary>>, cluster_ids) do
    case IP.Address.from_binary(address) do
      {:ok, prefix} ->
        decode_cluster_ids(rest, [prefix | cluster_ids])

      {:error, _reason} ->
        raise NOTIFICATION, code: :update_message, subcode: :invalid_nexthop_attribute
    end
  end

  @impl Encoder
  def encode(%__MODULE__{values: values}, fsm) do
    {data, length} =
      Enum.map_reduce(values, 0, fn address, length ->
        integer = IP.Address.to_integer(address)
        {<<integer::unit(32)-size(1)>>, length + 4}
      end)

    {data, length, fsm}
  end
end
