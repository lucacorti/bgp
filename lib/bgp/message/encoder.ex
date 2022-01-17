defmodule BGP.Message.Encoder do
  @moduledoc false

  alias BGP.Message.Encoder.Error

  @type t :: struct()
  @type data :: iodata()
  @type length :: non_neg_integer()
  @type options :: [extended_message: boolean(), four_octets_asns: boolean()]

  @callback decode(data(), options()) :: {:ok, t()} | {:error, Error.t()}
  @callback encode(t(), options()) :: data()
end
