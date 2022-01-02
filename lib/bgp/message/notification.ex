defmodule BGP.Message.Notification do
  @moduledoc false

  @type message_header ::
          :connection_not_synchronized
          | :bad_message_length
          | :bad_message_type

  @type open_message ::
          :unsupported_version_number
          | :bad_peer_as
          | :bad_bgp_identifier
          | :unsupported_optional_parameter
          | :authentication_failure
          | :unacceptable_hold_time

  @type update_message ::
          :malformed_attribute_list
          | :unrecognized_wellknown_attribute
          | :missing_wellknown_attribute
          | :attribute_flags_error
          | :attribute_length_error
          | :invalid_origin_attribute
          | :as_routing_loop
          | :invalid_nexthop_attribute
          | :optional_attribute_error
          | :invalid_network_field
          | :malformed_aspath

  @type fsm ::
          :unexpected_message_in_open_sent
          | :unexpected_message_in_open_confirm
          | :unexpected_message_in_established

  @type cease ::
          :maximum_number_of_prefixes_reached
          | :administrative_shutdown
          | :peer_deconfigured
          | :administrative_reset
          | :connection_rejected
          | :other_configuration_change
          | :connection_collision_resolution
          | :out_of_resources

  @type subcode :: message_header() | open_message() | update_message() | fsm() | :unspecific

  @type code ::
          :message_header
          | :open_message
          | :update_message
          | :hold_timer_expired
          | :fsm
          | :cease

  @type t :: %__MODULE__{
          code: pos_integer(),
          subcode: pos_integer(),
          data: binary()
        }

  @enforce_keys [:code]
  defstruct code: nil, subcode: :unspecific, data: <<>>

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(<<code::8, subcode::8, data::binary>>),
    do: {
      :ok,
      %__MODULE__{code: decode_code(code), subcode: decode_subcode(code, subcode), data: data}
    }

  defp decode_code(1), do: :message_header
  defp decode_code(2), do: :open_message
  defp decode_code(3), do: :update_message
  defp decode_code(4), do: :hold_timer_expired
  defp decode_code(5), do: :fsm
  defp decode_code(6), do: :cease

  defp decode_subcode(1, 1), do: :connection_not_synchronized
  defp decode_subcode(1, 2), do: :bad_message_length
  defp decode_subcode(1, 3), do: :bad_message_type

  defp decode_subcode(2, 1), do: :unsupported_version_number
  defp decode_subcode(2, 2), do: :bad_peer_as
  defp decode_subcode(2, 3), do: :bad_bgp_identifier
  defp decode_subcode(2, 4), do: :unsupported_optional_parameter
  defp decode_subcode(2, 5), do: :authentication_failure
  defp decode_subcode(2, 6), do: :unacceptable_hold_time

  defp decode_subcode(3, 1), do: :malformed_attribute_list
  defp decode_subcode(3, 2), do: :unrecognized_wellknown_attribute
  defp decode_subcode(3, 3), do: :missing_wellknown_attribute
  defp decode_subcode(3, 4), do: :attribute_flags_error
  defp decode_subcode(3, 5), do: :attribute_length_error
  defp decode_subcode(3, 6), do: :invalid_origin_attribute
  defp decode_subcode(3, 7), do: :as_routing_loop
  defp decode_subcode(3, 8), do: :invalid_nexthop_attribute
  defp decode_subcode(3, 9), do: :optional_attribute_error
  defp decode_subcode(3, 10), do: :invalid_network_field
  defp decode_subcode(3, 11), do: :malformed_aspath

  defp decode_subcode(5, 1), do: :unexpected_message_in_open_sent
  defp decode_subcode(5, 2), do: :unexpected_message_in_open_confirm
  defp decode_subcode(5, 3), do: :unexpected_message_in_established

  defp decode_subcode(6, 1), do: :maximum_number_of_prefixes_reached
  defp decode_subcode(6, 2), do: :administrative_shutdown
  defp decode_subcode(6, 3), do: :peer_deconfigured
  defp decode_subcode(6, 4), do: :administrative_reset
  defp decode_subcode(6, 5), do: :connection_rejected
  defp decode_subcode(6, 6), do: :other_configuration_change
  defp decode_subcode(6, 7), do: :connection_collision_resolution
  defp decode_subcode(6, 8), do: :out_of_resources

  defp decode_subcode(_code, 0), do: :unspecific

  @impl Encoder
  def encode(%__MODULE__{code: code, subcode: subcode, data: data}),
    do: [<<encode_code(code)::8>>, <<encode_subcode(code, subcode)::8>>, <<data::binary>>]

  defp encode_code(:message_header), do: 1
  defp encode_code(:open_message), do: 2
  defp encode_code(:update_message), do: 3
  defp encode_code(:hold_timer_expired), do: 4
  defp encode_code(:fsm), do: 5
  defp encode_code(:cease), do: 6

  defp encode_subcode(:message_header, :connection_not_synchronized), do: 1
  defp encode_subcode(:message_header, :bad_message_length), do: 2
  defp encode_subcode(:message_header, :bad_message_type), do: 3

  defp encode_subcode(:open_message, :unsupported_version_number), do: 1
  defp encode_subcode(:open_message, :bad_peer_as), do: 2
  defp encode_subcode(:open_message, :bad_bgp_identifier), do: 3
  defp encode_subcode(:open_message, :unsupported_optional_parameter), do: 4
  defp encode_subcode(:open_message, :authentication_failure), do: 5
  defp encode_subcode(:open_message, :unacceptable_hold_time), do: 6

  defp encode_subcode(:update_message, :malformed_attribute_list), do: 1
  defp encode_subcode(:update_message, :unrecognized_wellknown_attribute), do: 2
  defp encode_subcode(:update_message, :missing_wellknown_attribute), do: 3
  defp encode_subcode(:update_message, :attribute_flags_error), do: 4
  defp encode_subcode(:update_message, :attribute_length_error), do: 5
  defp encode_subcode(:update_message, :invalid_origin_attribute), do: 6
  defp encode_subcode(:update_message, :as_routing_loop), do: 7
  defp encode_subcode(:update_message, :invalid_nexthop_attribute), do: 8
  defp encode_subcode(:update_message, :optional_attribute_error), do: 9
  defp encode_subcode(:update_message, :invalid_network_field), do: 10
  defp encode_subcode(:update_message, :malformed_aspath), do: 11

  defp encode_subcode(:fsm, :unexpected_message_in_open_sent), do: 1
  defp encode_subcode(:fsm, :unexpected_message_in_open_confirm), do: 2
  defp encode_subcode(:fsm, :unexpected_message_in_established), do: 3

  defp encode_subcode(:cease, :maximum_number_of_prefixes_reached), do: 1
  defp encode_subcode(:cease, :administrative_shutdown), do: 2
  defp encode_subcode(:cease, :peer_deconfigured), do: 3
  defp encode_subcode(:cease, :administrative_reset), do: 4
  defp encode_subcode(:cease, :connection_rejected), do: 5
  defp encode_subcode(:cease, :other_configuration_change), do: 6
  defp encode_subcode(:cease, :connection_collision_resolution), do: 7
  defp encode_subcode(:cease, :out_of_resources), do: 8

  defp encode_subcode(_code, :unspecific), do: 0
end
