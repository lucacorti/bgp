defmodule BGP.Message.UPDATE.Attribute.IPV6ExtendedCommunities do
  @moduledoc false

  alias BGP.Message.Encoder

  ipv6_extended_communities = [
    {0x00, :transitive_ipv6_specific,
     [
       {0x02, :route_target},
       {0x03, :route_origin},
       {0x04, :ospf_v3_route_attributes},
       {0x05, :ipv6_address_specific_ifit_tail},
       {0x0B, :vrf_route_import},
       {0x0C, :flow_spec_redirect_to_ipv6},
       {0x0D, :flow_spec_redirect_ipv6_format},
       {0x10, :cisco_vpn_distinguisher},
       {0x11, :uuid_based_route_target},
       {0x12, :inter_area_p2mp_segmented_next_hop},
       {0x14, :vrf_recursive_next_hop},
       {0x15, :rt_derived_ec}
     ]},
    {0x40, :non_transitive_ipv6_specific, []}
  ]

  @type type ::
          unquote(
            Enum.map_join(ipv6_extended_communities, " | ", &inspect(elem(&1, 1)))
            |> Code.string_to_quoted!()
          )

  @type subtype ::
          unquote(
            Enum.flat_map(ipv6_extended_communities, &elem(&1, 2))
            |> Enum.map_join(" | ", &inspect(elem(&1, 1)))
            |> Code.string_to_quoted!()
          )

  @type extended_community :: {type(), subtype(), binary()}
  @type t :: %__MODULE__{extended_communities: [extended_community()]}
  defstruct extended_communities: []

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
       do: decode_extended_communities(rest, [{type, subtype} | extended_communities])

  @impl Encoder
  def encode(%__MODULE__{extended_communities: extended_communities}, _fsm),
    do: Enum.map(extended_communities, &encode_extended_community(&1))

  defp encode_extended_community({asn, data1, data2}), do: <<asn::32, data1::32, data2::32>>
end
