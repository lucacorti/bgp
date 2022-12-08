defmodule BGP.Message.Encoder do
  @moduledoc false

  alias BGP.FSM

  @type t :: struct()
  @type data :: iodata()
  @type length :: non_neg_integer()

  @callback decode(data(), FSM.t()) :: t() | :skip | no_return()
  @callback encode(t(), FSM.t()) :: {data(), length()} | no_return()
end
