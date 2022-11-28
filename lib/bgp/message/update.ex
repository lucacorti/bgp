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
  def decode(data, options) do
    {msg, rest} = decode_withdrawn_routes(%__MODULE__{}, data, options)
    {msg, rest} = decode_path_attributes(msg, rest, options)
    decode_nlri(msg, rest, options)
  end

  defp decode_withdrawn_routes(
         %__MODULE__{} = msg,
         <<length::16, prefixes::binary-size(length), rest::binary>>,
         options
       ) do
    {%{msg | withdrawn_routes: decode_prefixes(prefixes, [], options)}, rest}
  end

  defp decode_path_attributes(
         %__MODULE__{} = msg,
         <<length::16, attributes::binary-size(length), rest::binary>>,
         options
       ) do
    {%{msg | path_attributes: decode_attributes(attributes, [], options)}, rest}
  end

  defp decode_nlri(
         %__MODULE__{} = msg,
         nlri,
         options
       ) do
    %{msg | nlri: decode_prefixes(nlri, [], options)}
  end

  defp decode_attributes(
         <<0::1, 0::1, _partial::1, _extended::1, _unused::4, _rest::binary>>,
         _attributes,
         _options
       ) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end

  defp decode_attributes(
         <<0::1, _transitive::1, 1::1, _extended::1, _unused::4, _rest::binary>>,
         _attributes,
         _options
       ) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end

  defp decode_attributes(
         <<1::1, 0::1, 1::1, _extended::1, _unused::4, _rest::binary>>,
         _attributes,
         _options
       ) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end

  defp decode_attributes(<<>>, attributes, _options),
    do: Enum.reverse(attributes)

  defp decode_attributes(
         <<optional::1, transitive::1, _partial::1, extended::1, _unused::4, code::8,
           data::binary>>,
         attributes,
         options
       ) do
    length_size = 8 + 8 * extended
    <<length::integer-size(length_size), attribute::binary-size(length), rest::binary>> = data

    case {optional, transitive, Attribute.decode(<<code::8, attribute::binary>>, options)} do
      {_, _, {:ok, attribute}} ->
        decode_attributes(rest, [attribute | attributes], options)

      {_, _, :skip} ->
        decode_attributes(rest, attributes, options)
    end
  end

  defp decode_prefixes(<<>>, prefixes, _options), do: Enum.reverse(prefixes)

  defp decode_prefixes(
         <<length::8, prefix::binary-unit(1)-size(length), rest::binary>>,
         prefixes,
         options
       ) do
    with {:ok, prefix} <- Prefix.decode(prefix),
         do: decode_prefixes(rest, [prefix | prefixes], options)
  end

  @impl Encoder
  def encode(%__MODULE__{} = msg, options) do
    with {:ok, msg, data} <- encode_wr(msg, options),
         {:ok, msg, data} <- encode_pa(msg, data, options),
         {:ok, _msg, data} <- encode_nlri(msg, data, options) do
      Enum.reverse(data)
    end
  end

  defp encode_wr(%__MODULE__{withdrawn_routes: withdrawn_routes} = msg, options) do
    {wr_data, length} = encode_prefixes(withdrawn_routes, options)

    {:ok, msg, [[<<length::16>>, wr_data]]}
  end

  defp encode_pa(%__MODULE__{path_attributes: path_attributes} = msg, data, options) do
    {pa_data, length} = encode_attributes(path_attributes, options)

    {:ok, msg, [[<<length::16>>, pa_data] | data]}
  end

  defp encode_nlri(%__MODULE__{nlri: nlri} = msg, data, options) do
    {nlri_data, length} = encode_prefixes(nlri, options)

    {:ok, msg, [[<<length::8>>, nlri_data] | data]}
  end

  defp encode_attributes(attributes, options) do
    Enum.map_reduce(attributes, 0, fn attribute, length ->
      data = Attribute.encode(attribute, options)
      {data, length + IO.iodata_length(data)}
    end)
  end

  defp encode_prefixes(prefixes, _options) do
    Enum.map_reduce(prefixes, 0, fn prefix, length ->
      with {:ok, prefix, prefix_length} <- Prefix.encode(prefix),
           do: {[<<prefix_length::8>>, prefix], length + 1 + div(prefix_length, 8)}
    end)
  end
end
