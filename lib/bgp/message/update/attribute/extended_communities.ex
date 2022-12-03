defmodule BGP.Message.UPDATE.Attribute.ExtendedCommunities do
  @moduledoc false

  extended_communities = [
    {0x00, :transitive_2_octet_as_specific,
     [
       {0x02, :route_target},
       {0x03, :route_origin},
       {0x05, :ospf_domain_identifier},
       {0x08, :bgp_data_collection},
       {0x09, :source_as},
       {0x0A, :l2vpn_identifier},
       {0x10, :cisco_vpn_distinguisher},
       {0x13, :route_target_record},
       {0x15, :rt_derived_ec},
       {0x80, :virtual_network_identifier}
     ]},
    {0x01, :transitive_ipv4_specific,
     [
       {0x02, :route_target},
       {0x03, :route_origin},
       {0x04, :ipv4_address_specific_ifit_tail},
       {0x05, :ospf_domain_identifier},
       {0x07, :ospf_route_id},
       {0x09, :node_target},
       {0x0A, :l2vpn_identifier},
       {0x0B, :vrf_route_import},
       {0x0C, :flow_spec_redirect_to_ipv4},
       {0x10, :cisco_vpn_distinguisher},
       {0x12, :inter_area_p2mp_segmented_next_hop},
       {0x13, :route_target_record},
       {0x14, :vrf_recursive_next_hop},
       {0x15, :rt_derived_ec},
       {0x20, :mvpn_sa_rp_address}
     ]},
    {0x02, :transitive_4_octet_as_specific,
     [
       {0x02, :route_target},
       {0x03, :route_origin},
       {0x04, :generic},
       {0x05, :ospf_domain_identifier},
       {0x08, :bgp_data_collection},
       {0x09, :source_as},
       {0x10, :cisco_vpn_distinguisher},
       {0x13, :route_target_reecord},
       {0x15, :rt_derived_ec}
     ]},
    {0x03, :transitive_opaque,
     [
       {0x01, :cost_community},
       {0x03, :cp_orf},
       {0x04, :extranet_source},
       {0x05, :extranet_separation},
       {0x06, :ospf_route_type},
       {0x07, :additional_pmsi_tunnel_attribute_flags},
       {0x08, :context_label_space_id},
       {0x0B, :color},
       {0x0C, :encapsulation},
       {0x0D, :default_gateway},
       {0x0E, :ppmp_label},
       {0x14, :consistent_hash_sort_order},
       {0xAA, :load_balance}
     ]},
    {0x04, :qos_marking, []},
    {0x05, :cos_capability, []},
    {0x06, :evpn,
     [
       {0x00, :mac_mobility},
       {0x01, :esi_label},
       {0x02, :es_import_route_target},
       {0x03, :evpn_router_mac},
       {0x04, :evpn_layer_2_attributes},
       {0x05, :e_tree},
       {0x06, :df_election},
       {0x07, :i_sid},
       {0x08, :arp_nd},
       {0x09, :multicast_flags},
       {0x0A, :evi_rt_type_0},
       {0x0B, :evi_rt_type_1},
       {0x0C, :evi_rt_type_2},
       {0x0D, :evi_rt_type_3},
       {0x0E, :evpn_attachment_circuit},
       {0x0F, :service_carving_timestamp},
       {0x15, :rt_derived_ec}
     ]},
    {0x07, :flowspec_transitive, []},
    {0x08, :flowspec_redirect_mirror_to_ip_next_hop, []},
    {0x09, :flowspec_redirect_mirror_to_indirection_id, []},
    {0x0A, :transport_class, []},
    {0x0B, :sfc, []},
    {0x40, :non_transitive_2_octet_as_specific,
     [
       {0x04, :link_bandwidth},
       {0x80, :virtual_network_identifier}
     ]},
    {0x41, :non_transitive_ipv4_specific, [{0x09, :node_target}]},
    {0x42, :non_transitive_4_octet_as_specific, [{0x04, :generic}]},
    {0x43, :non_transitive_opaque,
     [
       {0x00, :bgp_origin_validation_state},
       {0x01, :cost_community},
       {0x02, :route_target},
       {0x15, :rt_derived_ec}
     ]},
    {0x44, :non_transitive_qos_marking, []},
    {0x47, :non_transitive_flowspec, []},
    {0x4A, :non_transitive_transport_class, []},
    {0x80, :generic_transitive_1,
     [
       {0x00, :ospf_route_type},
       {0x01, :ospf_router_id},
       {0x04, :security_group},
       {0x05, :osp_domain_identifier},
       {0x06, :flow_spec_traffic_rate_bytes},
       {0x07, :flow_spec_traffic_action},
       {0x08, :flow_spec_rt_redirect_as_2octet_format},
       {0x09, :flow_spec_traffic_remarking},
       {0x0A, :layer_2_info},
       {0x0B, :e_tree_info},
       {0x0C, :flow_spec_traffic_rate_packets},
       {0x0D, :flow_specification_for_sfc_classifiers},
       {0x84, :tag},
       {0x85, :origin_sub_cluster}
     ]},
    {0x81, :generic_transitive_2, [{0x08, :flow_spec_rt_redirect_ipv4_format}]},
    {0x82, :generic_transitive_3,
     [
       {0x04, :security_group_as4},
       {0x08, :flow_spec_rt_redirect_as_4octet_format},
       {0x84, :tag_4},
       {0x85, :origin_sub_cluster_4}
     ]}
  ]

  @type type ::
          unquote(
            Enum.map_join(extended_communities, " | ", &inspect(elem(&1, 1)))
            |> Code.string_to_quoted!()
          )

  @type subtype ::
          unquote(
            Enum.flat_map(extended_communities, &elem(&1, 2))
            |> Enum.map_join(" | ", &inspect(elem(&1, 1)))
            |> Code.string_to_quoted!()
          )

  @type extended_community :: {type(), subtype(), binary()}
  @type t :: %__MODULE__{extended_communities: [extended_community()]}
  defstruct extended_communities: []

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(<<data::binary>>, _fsm),
    do: %__MODULE__{extended_communities: decode_extended_communities(data, [])}

  defp decode_extended_communities(<<>>, extended_communities),
    do: Enum.reverse(extended_communities)

  defp decode_extended_communities(
         <<type::8, subtype::8, rest::binary>>,
         extended_communities
       ),
       do:
         decode_extended_communities(rest, [
           decode_extended_community(type, subtype) | extended_communities
         ])

  for {type, name, subtypes} <- extended_communities do
    for {subtype, subname} <- subtypes do
      defp decode_extended_community(unquote(type), unquote(subtype)),
        do: {unquote(name), unquote(subname)}
    end
  end

  defp decode_extended_community(type, subtype), do: {type, subtype}

  @impl Encoder
  def encode(%__MODULE__{extended_communities: extended_communities}, _fsm),
    do: Enum.map(extended_communities, &encode_extended_community(&1))

  defp encode_extended_community({asn, data1, data2}), do: <<asn::32, data1::32, data2::32>>
end
