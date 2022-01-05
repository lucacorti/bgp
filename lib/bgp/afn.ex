defmodule BGP.AFN do
  @moduledoc false

  @type code :: non_neg_integer()
  @type afi :: :reserved | :ipv4 | :ipv6
  @type safi :: :reserved | :nlri_unicast | :nlri_multicast

  @afis [
    {0, :reserved},
    {1, :ipv4},
    {2, :ipv6}
  ]

  @safis [
    {0, :reserved},
    {1, :nlri_unicast},
    {2, :nlri_multicast}
  ]

  @spec decode_afi(code()) :: afi()
  for {code, afi} <- @afis do
    def decode_afi(unquote(code)), do: unquote(afi)
  end

  def decode_afi(65_535), do: :reserved

  @spec decode_safi(code()) :: safi()
  for {code, afi} <- @safis do
    def decode_safi(unquote(code)), do: unquote(afi)
  end

  def decode_safi(255), do: :reserved

  @spec encode_afi(afi()) :: code()
  for {code, afi} <- @afis do
    def encode_afi(unquote(afi)), do: unquote(code)
  end

  @spec encode_safi(safi()) :: code()
  for {code, safi} <- @safis do
    def encode_safi(unquote(safi)), do: unquote(code)
  end
end
