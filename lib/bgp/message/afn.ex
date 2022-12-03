defmodule BGP.Message.AFN do
  @moduledoc false

  afis = [
    {0, :reserved},
    {1, :ipv4},
    {2, :ipv6}
  ]

  safis = [
    {0, :reserved},
    {1, :nlri_unicast},
    {2, :nlri_multicast}
  ]

  @type afi ::
          unquote(Enum.map_join(afis, " | ", &inspect(elem(&1, 1))) |> Code.string_to_quoted!())
  @type safi ::
          unquote(Enum.map_join(safis, " | ", &inspect(elem(&1, 1))) |> Code.string_to_quoted!())

  @type code :: non_neg_integer()

  @spec decode_afi(code()) :: {:ok, afi()} | :error
  for {code, afi} <- afis do
    def decode_afi(unquote(code)), do: {:ok, unquote(afi)}
  end

  def decode_afi(65_535), do: {:ok, :reserved}
  def decode_afi(_code), do: :error

  @spec decode_safi(code()) :: {:ok, safi()} | :error
  for {code, afi} <- safis do
    def decode_safi(unquote(code)), do: {:ok, unquote(afi)}
  end

  def decode_safi(255), do: {:ok, :reserved}
  def decode_safi(_code), do: :error

  @spec encode_afi(afi()) :: {:ok, code()} | :error
  for {code, afi} <- afis do
    def encode_afi(unquote(afi)), do: {:ok, unquote(code)}
  end

  def encode_afi(_afi), do: :error

  @spec encode_safi(safi()) :: {:ok, code()} | :error
  for {code, safi} <- safis do
    def encode_safi(unquote(safi)), do: {:ok, unquote(code)}
  end

  def encode_safi(_safi), do: :error
end
