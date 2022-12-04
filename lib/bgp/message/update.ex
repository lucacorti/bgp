defmodule BGP.Message.UPDATE do
  @moduledoc false

  alias BGP.Message.{Encoder, NOTIFICATION}
  alias BGP.Message.UPDATE.Attribute
  alias BGP.Prefix

  @type t :: %__MODULE__{
          withdrawn_routes: [Prefix.t()],
          path_attributes: [Encoder.t()],
          nlri: [Prefix.t()]
        }
  defstruct withdrawn_routes: [], path_attributes: [], nlri: []

  @behaviour Encoder

  @impl Encoder
  def decode(data, fsm) do
    {msg, rest} = decode_withdrawn_routes(%__MODULE__{}, data, fsm)
    {msg, rest} = decode_path_attributes(msg, rest, fsm)
    decode_nlri(msg, rest, fsm)
  end

  defp decode_withdrawn_routes(
         %__MODULE__{} = msg,
         <<length::16, prefixes::binary-size(length), rest::binary>>,
         fsm
       ) do
    {%{msg | withdrawn_routes: decode_prefixes(prefixes, [], fsm)}, rest}
  end

  defp decode_path_attributes(
         %__MODULE__{} = msg,
         <<length::16, attributes::binary-size(length), rest::binary>>,
         fsm
       ) do
    {%{msg | path_attributes: decode_attributes(attributes, [], fsm)}, rest}
  end

  defp decode_nlri(
         %__MODULE__{} = msg,
         nlri,
         fsm
       ) do
    %{msg | nlri: decode_prefixes(nlri, [], fsm)}
  end

  defp decode_attributes(
         <<0::1, 0::1, _partial::1, _extended::1, _unused::4, _rest::binary>>,
         _attributes,
         _fsm
       ) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end

  defp decode_attributes(
         <<0::1, _transitive::1, 1::1, _extended::1, _unused::4, _rest::binary>>,
         _attributes,
         _fsm
       ) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end

  defp decode_attributes(
         <<1::1, 0::1, 1::1, _extended::1, _unused::4, _rest::binary>>,
         _attributes,
         _fsm
       ) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end

  defp decode_attributes(<<>>, attributes, _fsm),
    do: Enum.reverse(attributes)

  defp decode_attributes(
         <<_optional::1, _transitive::1, _partial::1, extended::1, _unused::4, code::8,
           data::binary>>,
         attributes,
         fsm
       ) do
    length_size = 8 + 8 * extended
    <<length::integer-size(length_size), attribute::binary-size(length), rest::binary>> = data

    case Attribute.decode(<<code::8, attribute::binary>>, fsm) do
      :skip ->
        decode_attributes(rest, attributes, fsm)

      attribute ->
        decode_attributes(rest, [attribute | attributes], fsm)
    end
  end

  defp decode_prefixes(<<>>, prefixes, _fsm), do: Enum.reverse(prefixes)

  defp decode_prefixes(
         <<length::8, prefix::binary-unit(1)-size(length), rest::binary>>,
         prefixes,
         fsm
       ) do
    padding_length = rem(length, 8)
    <<_padding::binary-unit(1)-size(padding_length), unpadded::binary>> = rest
    fill_length = 32 - (length + padding_length)

    case Prefix.decode(<<prefix::binary, 0::size(fill_length)>>) do
      {:ok, prefix} ->
        decode_prefixes(unpadded, [prefix | prefixes], fsm)

      :error ->
        raise NOTIFICATION, code: :update_message, data: prefix
    end
  end

  @impl Encoder
  def encode(%__MODULE__{} = msg, fsm) do
    msg
    |> encode_wr(fsm)
    |> encode_pa(msg, fsm)
    |> encode_nlri(msg, fsm)
    |> Enum.reverse()
  end

  defp encode_wr(%__MODULE__{withdrawn_routes: withdrawn_routes}, fsm) do
    {wr_data, length} = encode_prefixes(withdrawn_routes, fsm)
    [[<<length::16>>, wr_data]]
  end

  defp encode_pa(data, %__MODULE__{path_attributes: path_attributes}, fsm) do
    {pa_data, length} = encode_attributes(path_attributes, fsm)
    [[<<length::16>>, pa_data] | data]
  end

  defp encode_nlri(data, %__MODULE__{nlri: []}, _fsm), do: data

  defp encode_nlri(data, %__MODULE__{nlri: nlri}, fsm) do
    {nlri_data, _length} = encode_prefixes(nlri, fsm)
    [nlri_data | data]
  end

  defp encode_attributes(attributes, fsm) do
    Enum.map_reduce(attributes, 0, fn attribute, length ->
      data = Attribute.encode(attribute, fsm)
      {data, length + IO.iodata_length(data)}
    end)
  end

  defp encode_prefixes(prefixes, _fsm) do
    Enum.map_reduce(prefixes, 0, fn prefix, length ->
      case Prefix.encode(prefix) do
        {:ok, prefix, prefix_length} ->
          {[<<prefix_length::8>>, prefix], length + 1 + div(prefix_length, 8)}

        :error ->
          raise NOTIFICATION, code: :update_message
      end
    end)
  end
end
