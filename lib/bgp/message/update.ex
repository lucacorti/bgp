defmodule BGP.Message.Update do
  @moduledoc false

  alias BGP.Message.Encoder
  alias BGP.Message.Update.Attribute
  alias BGP.Prefix

  @type t :: %__MODULE__{
          withdrawn_routes: [Prefix.t()],
          path_attributes: [Encoder.t()],
          nlri: [Prefix.t()]
        }
  defstruct withdrawn_routes: [], path_attributes: [], nlri: []

  @behaviour Encoder

  @impl Encoder
  def decode(data) do
    with {:ok, msg, rest} <- decode_withdrawn_routes(%__MODULE__{}, data),
         {:ok, msg, rest} <- decode_path_attributes(msg, rest) do
      decode_nlri(msg, rest)
    end
  end

  defp decode_withdrawn_routes(
         %__MODULE__{} = msg,
         <<length::16, prefixes::binary()-size(length), rest::binary>>
       ) do
    {:ok, %{msg | withdrawn_routes: decode_prefixes(prefixes, [])}, rest}
  end

  defp decode_path_attributes(
         %__MODULE__{} = msg,
         <<length::16, attributes::binary()-size(length), rest::binary>>
       ) do
    {:ok, %{msg | path_attributes: decode_attributes(attributes, [])}, rest}
  end

  defp decode_nlri(
         %__MODULE__{} = msg,
         nlri
       ) do
    {:ok, %{msg | nlri: decode_prefixes(nlri, [])}}
  end

  defp decode_attributes(<<>>, attributes), do: Enum.reverse(attributes)

  defp decode_attributes(
         <<0::1, 0::1, _partial::1, _extended::1, _unused::4, _rest::binary>>,
         _attributes
       ),
       do: :error

  defp decode_attributes(
         <<0::1, _transitive::1, 1::1, _extended::1, _unused::4, _rest::binary>>,
         _attributes
       ),
       do: :error

  defp decode_attributes(
         <<1::1, 0::1, 1::1, _extended::1, _unused::4, _rest::binary>>,
         _attributes
       ),
       do: :error

  defp decode_attributes(
         <<_optional::1, _transitive::1, _partial::1, extended::1, _unused::4, code::8,
           data::binary>>,
         attributes
       ) do
    length_size = if extended == 1, do: 16, else: 8
    <<length::integer()-size(length_size), attribute::binary()-size(length), rest::binary>> = data

    with {:ok, attribute} <- Attribute.decode(<<code::8, attribute::binary>>) do
      decode_attributes(rest, [attribute | attributes])
    end
  end

  defp decode_prefixes(<<>>, prefixes), do: Enum.reverse(prefixes)

  defp decode_prefixes(
         <<length::8, prefix::binary()-unit(1)-size(length), rest::binary>>,
         prefixes
       ) do
    with {:ok, prefix} <- Prefix.decode(prefix),
         do: decode_prefixes(rest, [prefix | prefixes])
  end

  @impl Encoder
  def encode(%__MODULE__{} = msg) do
    with {:ok, msg, data} <- encode_wr(msg),
         {:ok, msg, data} <- encode_pa(msg, data),
         {:ok, _msg, data} <- encode_nlri(msg, data) do
      Enum.reverse(data)
    end
  end

  defp encode_wr(%__MODULE__{withdrawn_routes: w_r} = msg) do
    {wr_data, length} = encode_prefixes(w_r)

    {:ok, msg, [[<<length::16>>, wr_data]]}
  end

  defp encode_pa(%__MODULE__{path_attributes: p_a} = msg, data) do
    {pa_data, length} = encode_attributes(p_a)

    {:ok, msg, [[<<length::16>>, pa_data] | data]}
  end

  defp encode_nlri(%__MODULE__{nlri: nlri} = msg, data) do
    {nlri_data, length} = encode_prefixes(nlri)

    {:ok, msg, [[<<length::8>>, nlri_data] | data]}
  end

  defp encode_attributes(attributes) do
    Enum.map_reduce(attributes, 0, fn attribute, length ->
      data = Attribute.encode(attribute)
      {data, length + IO.iodata_length(data)}
    end)
  end

  defp encode_prefixes(prefixes) do
    Enum.map_reduce(prefixes, 0, fn prefix, length ->
      with {:ok, prefix, prefix_length} <- Prefix.encode(prefix),
           do: {[<<prefix_length::8>>, prefix], length + 8 + prefix_length}
    end)
  end
end
