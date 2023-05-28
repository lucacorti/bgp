defmodule BGP.Message.Encoder do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.FSM

  @type t :: struct()
  @type data :: iodata()
  @type length :: non_neg_integer()

  @callback decode(data(), FSM.t()) :: {t(), FSM.t()} | no_return()
  @callback encode(t(), FSM.t()) :: {data(), length(), FSM.t()} | no_return()
end
