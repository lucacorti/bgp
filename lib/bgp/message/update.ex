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

  @header_size 19
  @max_size 4_096
  @extended_max_size 65_535

  @behaviour Encoder

  @impl Encoder
  def decode(
        <<
          withdrawn_length::16,
          withdrawn::binary-size(withdrawn_length),
          attributes_length::16,
          attributes::binary-size(attributes_length),
          nlri::binary
        >>,
        fsm
      )
      when (fsm.extended_message and
              withdrawn_length + attributes_length + @header_size + 4 <= @extended_max_size) or
             withdrawn_length + attributes_length + @header_size + 4 <= @max_size do
    %__MODULE__{
      withdrawn_routes: Message.decode_prefixes(withdrawn),
      path_attributes: decode_attributes(attributes, [], fsm),
      nlri: Message.decode_prefixes(nlri)
    }
  end

  def decode(_data, _fsm) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end

  defp decode_attributes(<<>>, attributes, _fsm), do: Enum.reverse(attributes)

  defp decode_attributes(<<header::binary-size(2), data::binary>>, attributes, fsm) do
    <<_other_flags::3, extended::1, _unused::4, _code::8>> = header
    size = 8 + 8 * extended
    <<length::integer-size(size), attribute::binary-size(length), rest::binary>> = data

    attribute =
      Attribute.decode(<<header::binary, length::integer-size(size), attribute::binary>>, fsm)

    decode_attributes(rest, [attribute | attributes], fsm)
  end

  @impl Encoder
  def encode(%__MODULE__{} = msg, fsm) do
    {wr_data, wr_length} = Message.encode_prefixes(msg.withdrawn_routes)
    {pa_data, pa_length} = encode_attributes(msg.path_attributes, fsm)
    {nlri_data, nlri_length} = Message.encode_prefixes(msg.nlri)

    {
      [<<wr_length::16>>, wr_data, <<pa_length::16>>, pa_data, nlri_data],
      2 + wr_length + 2 + pa_length + nlri_length
    }
  end

  defp encode_attributes(attributes, fsm) do
    Enum.map_reduce(attributes, 0, fn attribute, length ->
      {data, attribute_length} = Attribute.encode(attribute, fsm)
      {data, length + attribute_length}
    end)
  end
end
