defmodule BGP.Message.UPDATE do
  @moduledoc false

  alias BGP.Message
  alias BGP.Message.{Encoder, NOTIFICATION, UPDATE.Attribute}

  @type t :: %__MODULE__{
          withdrawn_routes: [IP.Prefix.t()],
          path_attributes: [Encoder.t()],
          nlri: [IP.Prefix.t()]
        }
  defstruct withdrawn_routes: [], path_attributes: [], nlri: []

  @behaviour Encoder

  @impl Encoder
  def decode(data, fsm) do
    {msg, rest} = decode_withdrawn_routes(%__MODULE__{}, data)
    {msg, rest} = decode_path_attributes(msg, rest, fsm)
    %{msg | nlri: Message.decode_prefixes(rest)}
  end

  defp decode_withdrawn_routes(
         %__MODULE__{} = msg,
         <<length::16, prefixes::binary-size(length), rest::binary>>
       ) do
    {%{msg | withdrawn_routes: Message.decode_prefixes(prefixes)}, rest}
  end

  defp decode_path_attributes(
         %__MODULE__{} = msg,
         <<length::16, attributes::binary-size(length), rest::binary>>,
         fsm
       ) do
    {%{msg | path_attributes: decode_attributes(attributes, [], fsm)}, rest}
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
    <<length::integer-size(8 + 8 * extended), attribute::binary-size(length), rest::binary>> =
      data

    case Attribute.decode(<<code::8, attribute::binary>>, fsm) do
      :skip ->
        decode_attributes(rest, attributes, fsm)

      attribute ->
        decode_attributes(rest, [attribute | attributes], fsm)
    end
  end

  @impl Encoder
  def encode(%__MODULE__{} = msg, fsm) do
    {wr_data, wr_length} = Message.encode_prefixes(msg.withdrawn_routes)
    {pa_data, pa_length} = encode_attributes(msg.path_attributes, fsm)
    {nlri_data, _nlri_length} = Message.encode_prefixes(msg.nlri)
    [<<wr_length::16>>, wr_data, <<pa_length::16>>, pa_data, nlri_data]
  end

  defp encode_attributes(attributes, fsm) do
    Enum.map_reduce(attributes, 0, fn attribute, length ->
      data = Attribute.encode(attribute, fsm)
      {data, length + IO.iodata_length(data)}
    end)
  end
end
