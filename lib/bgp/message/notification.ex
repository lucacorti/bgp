defmodule BGP.Message.Notification do
  @moduledoc """
  BGP NOTIFICATION
  """
  @type t :: %__MODULE__{
          code: pos_integer(),
          subcode: pos_integer(),
          data: binary()
        }

  @enforce_keys [:code, :subcode]
  defstruct code: nil, subcode: nil, data: nil

  alias BGP.Message

  @behaviour Message

  @impl Message
  def decode(<<code::8, subcode::8, data::binary>>, _length),
    do: {:ok, %__MODULE__{code: code, subcode: subcode, data: data}}

  @impl Message
  def encode(%__MODULE__{} = msg), do: [<<msg.code::8>>, <<msg.subcode::8>>, <<msg.data::binary>>]
end
