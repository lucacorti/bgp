defmodule BGP.Prefix do
  @type t :: :inet.ip_address()

  @spec decode(binary()) :: t()
  def decode(<<a::8, b::8, c::8, d::8>>), do: {a, b, c, d}

  def decode(<<a::8, b::8, c::8, d::8, e::8, f::8, g::8, h::8>>),
    do: {a, b, c, d, e, f, g, h}

  @spec encode(t()) :: {binary(), pos_integer()}
  def encode({a, b, c, d}), do: {<<32::8, a::8, b::8, c::8, d::8>>, 32}

  def encode({a, b, c, d, e, f, g, h}),
    do: {<<128::8, a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>>, 128}
end
