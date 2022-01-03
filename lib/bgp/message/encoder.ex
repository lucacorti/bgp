defmodule BGP.Message.Encoder do
  @moduledoc false

  alias BGP.Message.Notification

  @type t :: struct()
  @type data :: iodata()
  @type length :: non_neg_integer()
  @type options :: [four_octets_asns: boolean()]
  @callback decode(data(), options()) :: {:ok, t()} | {:error, Notification.t()}
  @callback encode(t(), options()) :: data()
end
