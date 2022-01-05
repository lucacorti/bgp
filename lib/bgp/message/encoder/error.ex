defmodule BGP.Message.Encoder.Error do
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

  @type t :: %__MODULE__{code: code(), subcode: subcode()}
  @enforce_keys [:code]
  defstruct code: nil, subcode: :unspecific
end
