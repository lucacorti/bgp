defmodule BGP.Message.Encoder do
  @moduledoc false

  @type t :: struct()
  @type data :: iodata()
  @type length :: non_neg_integer()
  @type options :: [extended_message: boolean(), four_octets_asns: boolean()]

  @callback decode(data(), options()) :: t() | :skip | no_return()
  @callback encode(t(), options()) :: data() | no_return()
end
