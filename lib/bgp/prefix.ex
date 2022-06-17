defmodule BGP.Prefix do
  @moduledoc false

  @type size :: pos_integer()
  @type t :: :inet.ip_address()

  @spec decode(binary()) :: {:ok, t()} | :error
  def decode(<<a::8, b::8, c::8, d::8>>), do: {:ok, {a, b, c, d}}

  def decode(<<a::8, b::8, c::8, d::8, e::8, f::8, g::8, h::8>>),
    do: {:ok, {a, b, c, d, e, f, g, h}}

  def decode(_data), do: :error

  @spec encode(t()) :: {:ok, binary(), size()} | :error
  def encode({a, b, c, d}), do: {:ok, <<a::8, b::8, c::8, d::8>>, 32}

  def encode({a, b, c, d, e, f, g, h}),
    do: {:ok, <<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>>, 128}

  def encode(_address), do: :error

  @spec parse(String.t()) :: {:ok, t()} | {:error, :invalid}
  def parse(address) do
    case address
         |> String.to_charlist()
         |> :inet.parse_address() do
      {:ok, prefix} -> {:ok, prefix}
      {:error, :einval} -> {:error, :invalid}
    end
  end

  @spec to_string(t()) :: {:ok, String.t()} | {:error, :invalid}
  def to_string(prefix) do
    case :inet.ntoa(prefix) do
      {:error, :einval} -> {:error, :invalid}
      address -> {:ok, Kernel.to_string(address)}
    end
  end

  @spec to_integer(t()) :: non_neg_integer()
  def to_integer({a, b, c, d}) do
    Bitwise.<<<(a, 24) +
      Bitwise.<<<(b, 16) +
      Bitwise.<<<(c, 8) +
      d
  end

  def to_integer({a, b, c, d, e, f, g, h}) do
    Bitwise.<<<(a, 112) +
      Bitwise.<<<(b, 96) +
      Bitwise.<<<(c, 80) +
      Bitwise.<<<(d, 64) +
      Bitwise.<<<(e, 48) +
      Bitwise.<<<(f, 32) +
      Bitwise.<<<(g, 16) +
      h
  end
end
