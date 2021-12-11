defmodule BGP.Attribute.Flags do
  @type t :: %__MODULE__{
          optional: boolean(),
          transitive: boolean(),
          partial: boolean(),
          extended: boolean()
        }
  @enforce_keys [:optional, :transitive, :partial, :extended]
  defstruct optional: false, transitive: false, partial: false, extended: false

  @spec decode(binary()) :: {:ok, t()} | :error
  def decode(<<0::1, 0::1, _partial::1, _extended::1, _unused::4>>),
    do: :error

  def decode(<<0::1, _transitive::1, 1::1, _extended::1, _unused::4>>),
    do: :error

  def decode(<<1::1, 0::1, 1::1, _extended::1, _unused::4>>),
    do: :error

  def decode(<<optional::1, transitive::1, partial::1, extended::1, _unused::4>>) do
    {
      :ok,
      %__MODULE__{
        optional: int_to_bool(optional),
        transitive: int_to_bool(transitive),
        partial: int_to_bool(partial),
        extended: int_to_bool(extended)
      }
    }
  end

  @spec encode(t()) :: binary()
  def encode(%__MODULE__{
        optional: optional,
        transitive: transitive,
        partial: partial,
        extended: extended
      }) do
    <<
      bool_to_int(optional)::1,
      bool_to_int(transitive)::1,
      bool_to_int(partial)::1,
      bool_to_int(extended)::1,
      0::4
    >>
  end

  defp bool_to_int(false), do: 0
  defp bool_to_int(true), do: 1

  defp int_to_bool(0), do: false
  defp int_to_bool(1), do: true
end
