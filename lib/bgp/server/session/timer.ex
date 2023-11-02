defmodule BGP.Server.Session.Timer do
  @moduledoc "BGP Session Timer"

  @type seconds :: non_neg_integer()

  @type t :: %__MODULE__{
          enabled?: boolean(),
          seconds: seconds(),
          running?: boolean(),
          value: seconds()
        }
  @enforce_keys [:enabled?, :seconds, :value]
  defstruct enabled?: true, seconds: nil, running?: false, value: nil

  @spec new(seconds(), boolean()) :: t()
  def new(seconds, enabled?),
    do: %__MODULE__{enabled?: enabled?, seconds: seconds, value: seconds}

  @spec set(t(), seconds() | nil) :: t()
  def set(%__MODULE__{} = timer, seconds),
    do: %{timer | value: seconds || timer.seconds}

  @spec restart(t(), seconds() | nil) :: t()
  def restart(%__MODULE__{enabled?: enabled?} = timer, seconds),
    do: %{set(timer, seconds) | running?: enabled?}

  @spec start(t()) :: t()
  def start(%__MODULE__{enabled?: enabled?} = timer), do: %{timer | running?: enabled?}

  @spec stop(t()) :: t()
  def stop(%__MODULE__{} = timer), do: %{timer | running?: false}
end
