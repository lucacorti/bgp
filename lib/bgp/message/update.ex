defmodule BGP.Message.UPDATE do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.Message
  alias BGP.Message.{Encoder, NOTIFICATION, UPDATE.Attribute}

  @type t :: %__MODULE__{
          withdrawn_routes: [IP.Prefix.t()],
          path_attributes: [Attribute.t()],
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
    {attributes, fsm} = decode_attributes(attributes, [], fsm)

    with {:ok, withdrawn_prefixes} <- Message.decode_prefixes(withdrawn),
         {:ok, nlri_prefixes} <- Message.decode_prefixes(nlri) do
      {
        %__MODULE__{
          withdrawn_routes: withdrawn_prefixes,
          path_attributes: attributes,
          nlri: nlri_prefixes
        },
        fsm
      }
    else
      {:error, data} ->
        raise NOTIFICATION, code: :update_message, data: data
    end
  end

  def decode(_data, _fsm) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end

  defp decode_attributes(<<>>, attributes, fsm), do: {Enum.reverse(attributes), fsm}

  defp decode_attributes(<<header::binary-size(2), data::binary>>, attributes, fsm) do
    <<_other_flags::3, extended::1, _unused::4, _code::8>> = header
    size = 8 + 8 * extended
    <<length::integer-size(size), attribute::binary-size(length), rest::binary>> = data

    {attribute, fsm} =
      Attribute.decode(<<header::binary, length::integer-size(size), attribute::binary>>, fsm)

    decode_attributes(rest, [attribute | attributes], fsm)
  end

  @impl Encoder
  def encode(%__MODULE__{} = msg, fsm) do
    {wr_data, wr_length} = Message.encode_prefixes(msg.withdrawn_routes)
    {pa_data, pa_length, fsm} = encode_attributes(msg.path_attributes, fsm)
    {nlri_data, nlri_length} = Message.encode_prefixes(msg.nlri)

    {
      [<<wr_length::16>>, wr_data, <<pa_length::16>>, pa_data, nlri_data],
      2 + wr_length + 2 + pa_length + nlri_length,
      fsm
    }
  end

  defp encode_attributes(attributes, fsm) do
    {data, {length, fsm}} =
      Enum.map_reduce(attributes, {0, fsm}, fn attribute, {length, fsm} ->
        {data, attribute_length, fsm} = Attribute.encode(attribute, fsm)
        {data, {length + attribute_length, fsm}}
      end)

    {data, length, fsm}
  end
end
