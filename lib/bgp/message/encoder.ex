defmodule BGP.Message.Encoder do
  @moduledoc false

  alias BGP.Server.FSM

  @type t :: struct()
  @type data :: iodata()
  @type length :: non_neg_integer()

  @callback decode(data(), FSM.options()) :: t() | :skip | no_return()
  @callback encode(t(), FSM.options()) :: data() | no_return()
end
