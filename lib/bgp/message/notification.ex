defmodule BGP.Message.NOTIFICATION do
  @moduledoc false

  alias BGP.Message.Encoder.Error

  errors = [
    {
      1,
      :message_header,
      [
        {1, :connection_not_synchronized},
        {2, :bad_message_length},
        {3, :bad_message_type}
      ]
    },
    {
      2,
      :open_message,
      [
        {1, :unsupported_version_number},
        {2, :bad_peer_as},
        {3, :bad_bgp_identifier},
        {4, :unsupported_optional_parameter},
        {5, :authentication_failure},
        {6, :unacceptable_hold_time}
      ]
    },
    {
      3,
      :update_message,
      [
        {1, :malformed_attribute_list},
        {2, :unrecognized_wellknown_attribute},
        {3, :missing_wellknown_attribute},
        {4, :attribute_flags_error},
        {5, :attribute_length_error},
        {6, :invalid_origin_attribute},
        {7, :as_routing_loop},
        {8, :invalid_nexthop_attribute},
        {9, :optional_attribute_error},
        {10, :invalid_network_field},
        {11, :malformed_aspath}
      ]
    },
    {4, :hold_timer_expired, []},
    {
      5,
      :fsm,
      [
        {1, :unexpected_message_in_open_sent},
        {2, :unexpected_message_in_open_confirm},
        {3, :unexpected_message_in_established}
      ]
    },
    {
      6,
      :cease,
      [
        {1, :maximum_number_of_prefixes_reached},
        {2, :administrative_shutdown},
        {3, :peer_deconfigured},
        {4, :administrative_reset},
        {5, :connection_rejected},
        {6, :other_configuration_change},
        {7, :connection_collision_resolution},
        {8, :out_of_resources}
      ]
    },
    {7, :route_refresh_message, [{1, :invalid_message_length}]}
  ]

  for {_code, name, subcodes} <- errors, not Enum.empty?(subcodes) do
    @type unquote(
            ("#{name} :: " <> Enum.map_join(subcodes, " | ", &inspect(elem(&1, 1))))
            |> Code.string_to_quoted!()
          )
  end

  @type subcode ::
          unquote(
            ((errors
              |> Enum.reject(fn
                {_, _, []} -> true
                _ -> false
              end)
              |> Enum.map_join(" | ", &to_string(elem(&1, 1)))) <> " | :unspecific")
            |> Code.string_to_quoted!()
          )

  @type code ::
          unquote(
            errors
            |> Enum.map_join(" | ", &inspect(elem(&1, 1)))
            |> Code.string_to_quoted!()
          )

  @type data :: binary()

  @type t :: %__MODULE__{
          code: code(),
          subcode: subcode(),
          data: data()
        }

  @enforce_keys [:code]
  defstruct code: nil, subcode: :unspecific, data: <<>>

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(<<code::8, subcode::8, data::binary>>, _options),
    do: {
      :ok,
      %__MODULE__{code: decode_code(code), subcode: decode_subcode(code, subcode), data: data}
    }

  def decode(_notification, _options),
    do: {:error, %Error{code: :message_header, subcode: :bad_message_length}}

  @impl Encoder
  def encode(%__MODULE__{code: code, subcode: subcode, data: data}, _options),
    do: [<<encode_code(code)::8>>, <<encode_subcode(code, subcode)::8>>, <<data::binary>>]

  for {code, reason, _subcodes} <- errors do
    defp decode_code(unquote(code)), do: unquote(reason)
  end

  for {code, _reason, subcodes} <- errors do
    for {subcode, subreason} <- subcodes do
      defp decode_subcode(unquote(code), unquote(subcode)),
        do: unquote(subreason)
    end
  end

  defp decode_subcode(_code, 0), do: :unspecific

  for {code, reason, _subcodes} <- errors do
    defp encode_code(unquote(reason)), do: unquote(code)
  end

  for {_code, reason, subcodes} <- errors do
    for {subcode, subreason} <- subcodes do
      defp encode_subcode(unquote(reason), unquote(subreason)), do: unquote(subcode)
    end
  end

  defp encode_subcode(_code, :unspecific), do: 0
end
