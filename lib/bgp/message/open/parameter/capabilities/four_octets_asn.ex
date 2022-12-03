defmodule BGP.Message.OPEN.Parameter.Capabilities.FourOctetsASN do
  @moduledoc false

  alias BGP.Message.{Encoder, NOTIFICATION}

  @type t :: %__MODULE__{asn: BGP.asn()}
  @enforce_keys [:asn]
  defstruct asn: nil

  @behaviour Encoder

  @impl Encoder
  def decode(<<asn::32>>, _fsm), do: %__MODULE__{asn: asn}

  def decode(_data, _fsm) do
    raise NOTIFICATION, code: :open_message
  end

  @impl Encoder
  def encode(%__MODULE__{asn: asn}, _fsm), do: [<<asn::32>>]

  def encode(_msg, _fsm) do
    raise NOTIFICATION, code: :open_message
  end
end
