defmodule BGP.Message.Encoder do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.Server.Session

  @type t :: struct()
  @type data :: iodata()
  @type length :: non_neg_integer()

  @callback decode(data(), Session.data()) :: t() | no_return()
  @callback encode(t(), Session.data()) :: {data(), length()} | no_return()
end
