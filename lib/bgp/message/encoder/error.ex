defmodule BGP.Message.Encoder.Error do
  @moduledoc false

  alias BGP.Message.NOTIFICATION

  @type t :: %__MODULE__{
          code: NOTIFICATION.code(),
          subcode: NOTIFICATION.subcode(),
          data: NOTIFICATION.data()
        }
  @enforce_keys [:code]
  defstruct code: nil, subcode: :unspecific, data: <<>>

  @spec to_notification(t()) :: NOTIFICATION.t()
  def to_notification(%__MODULE__{} = error),
    do: %NOTIFICATION{code: error.code, subcode: error.subcode, data: error.data}
end
