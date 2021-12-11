defmodule BGP.Message.Update do
  alias BGP.{Attribute, Message, Prefix}

  @type t :: %__MODULE__{
          withdrawn_routes: [Prefix.t()],
          path_attributes: [Attribute.t()],
          nlri: [Prefix.t()]
        }
  defstruct withdrawn_routes: [], path_attributes: [], nlri: []

  @behaviour Message

  @impl Message
  def decode(data, _length) do
    with {:ok, msg, rest} <- decode_withdrawn_routes(%__MODULE__{}, data),
         {:ok, msg, rest} <- decode_path_attributes(msg, rest) do
      decode_nlri(msg, rest)
    end
  end

  defp decode_withdrawn_routes(%__MODULE__{} = msg, <<length::16, data::binary>>) do
    with {:ok, prefixes, rest} <- decode_prefixes([], data, length),
         do: {:ok, %{msg | withdrawn_routes: Enum.reverse(prefixes)}, rest}
  end

  defp decode_path_attributes(msg, <<length::16, data::binary>>) do
    with {:ok, msg, rest} <- decode_attr(msg, data, length),
         do: {:ok, msg, rest}
  end

  defp decode_attr(%__MODULE__{path_attributes: p_a} = msg, data, 0),
    do: {:ok, %{msg | path_attributes: Enum.reverse(p_a)}, data}

  defp decode_attr(
         %__MODULE__{path_attributes: p_a} = msg,
         <<flags::8, type::8, data::binary>>,
         total
       ),
       do: decode_prefixes(%{msg | path_attributes: [{flags, type} | p_a]}, data, total)

  defp decode_nlri(%__MODULE__{} = msg, <<length::16, data::binary>>) do
    with {:ok, prefixes, _rest} <- decode_prefixes([], data, length),
         do: {:ok, %{msg | nlri: Enum.reverse(prefixes)}}
  end

  defp decode_prefixes(prefixes, data, 0), do: {:ok, prefixes, data}

  defp decode_prefixes(prefixes, <<length::8, data::binary>>, total) do
    byte_length = div(length, 8)
    IO.inspect(data, label: "data")
    IO.inspect(total, label: "total")
    IO.inspect(length, label: "prefix length")

    address =
      data
      |> binary_part(0, byte_length)
      |> Prefix.decode()
      |> IO.inspect(label: "prefix")

    rest =
      binary_part(
        data,
        IO.inspect(byte_length, label: "from"),
        IO.inspect(byte_size(data) - byte_length, label: "take")
      )
      |> IO.inspect(label: "rest")

    decode_prefixes([address | prefixes], rest, total - (length + 1))
  end

  @impl Message
  def encode(%__MODULE__{} = msg) do
    with {:ok, msg, data} <- encode_wr(msg),
         {:ok, msg, data} <- encode_pa(msg, data),
         {:ok, _msg, data} <- encode_nlri(msg, data) do
      Enum.reverse(data)
    end
  end

  defp encode_wr(%__MODULE__{withdrawn_routes: w_r} = msg) do
    {wr_data, length} =
      Enum.map_reduce(w_r, 0, fn prefix, length ->
        {prefix, prefix_length} = Prefix.encode(prefix)
        {prefix, length + prefix_length + 1}
      end)

    {:ok, msg, [[<<length::16>>, wr_data]]}
  end

  defp encode_pa(%__MODULE__{path_attributes: p_a} = msg, data) do
    {pa_data, length} =
      Enum.map_reduce(p_a, 0, fn prefix, length ->
        {prefix, prefix_length} = Prefix.encode(prefix)
        {prefix, length + prefix_length + 1}
      end)

    {:ok, msg, [[<<length::16>>, pa_data] | data]}
  end

  defp encode_nlri(%__MODULE__{nlri: nlri} = msg, data) do
    {nlri_data, length} =
      Enum.map_reduce(nlri, 0, fn prefix, length ->
        {prefix, prefix_length} = Prefix.encode(prefix)
        {prefix, length + prefix_length + 1}
      end)

    {:ok, msg, [[<<length::16>>, nlri_data] | data]}
  end
end
