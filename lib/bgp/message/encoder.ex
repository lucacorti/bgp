defmodule BGP.Message.Encoder do
  @moduledoc false

  alias BGP.Message.Notification

  @type t :: struct()
  @type data :: iodata()
  @type length :: non_neg_integer()

  @callback decode(data()) :: {:ok, t()} | {:error, Notification.t()}
  @callback encode(t()) :: data()
end
