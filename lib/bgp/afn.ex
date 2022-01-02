defmodule BGP.AFN do
  @moduledoc false

  @type code :: non_neg_integer()
  @type afi :: :reserved | :ipv4 | :ipv6
  @type safi :: :reserved | :nlri_unicast | :nlri_multicast

  def decode_afi(0), do: :reserved
  def decode_afi(1), do: :ipv4
  def decode_afi(2), do: :ipv6
  def decode_afi(65_535), do: :reserved

  def decode_safi(0), do: :reserved
  def decode_safi(1), do: :nlri_unicast
  def decode_safi(2), do: :nlri_multicast
  def decode_safi(255), do: :reserved

  def encode_afi(:ipv4), do: 1
  def encode_afi(:ipv6), do: 2
  def encode_afi(:reserved), do: 65_535

  def encode_safi(:reserved), do: 0
  def encode_safi(:nlri_unicast), do: 1
  def encode_safi(:nlri_multicast), do: 2
end
