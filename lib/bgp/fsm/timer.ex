defmodule BGP.FSM.Timer do
  @moduledoc "BGP Finite State Machine Timer"

  @type name :: atom()
  @type seconds :: non_neg_integer()
  @type t :: {reference() | nil, seconds()}

  @spec new(seconds()) :: t()
  def new(seconds), do: {nil, seconds}

  @spec init(t(), seconds()) :: t()
  def init({ref, _seconds}, seconds),
    do: {ref, seconds}

  @spec running?(t()) :: boolean()
  def running?({nil, _seconds}), do: false
  def running?({_ref, _seconds}), do: true

  @spec start(t(), name()) :: t()
  def start({nil, seconds}, name),
    do: {Process.send_after(self(), {:timer, name, :expired}, seconds * 1_000), seconds}

  def start({_ref, _seconds} = timer, _name), do: timer

  @spec stop(t()) :: t()
  def stop({nil, _seconds} = timer), do: timer

  def stop({ref, seconds}) do
    with :ok <- Process.cancel_timer(ref, info: false),
         do: {nil, seconds}
  end

  @spec seconds(t) :: seconds()
  def seconds({_ref, seconds}), do: seconds
end
