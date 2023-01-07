defmodule BGP.Message.OPEN.Parameter.Capabilities.FourOctetsASN do
  @moduledoc false

  alias BGP.FSM
  alias BGP.Message.{Encoder, NOTIFICATION}

  @type t :: %__MODULE__{asn: BGP.asn()}
  @enforce_keys [:asn]
  defstruct asn: nil

  @behaviour Encoder

  @impl Encoder
  def decode(<<asn::32>>, %FSM{} = fsm),
    do: {%__MODULE__{asn: asn}, %FSM{fsm | four_octets: true, ibgp: asn == fsm.asn}}

  def decode(_data, _fsm) do
    raise NOTIFICATION, code: :open_message
  end

  @impl Encoder
  def encode(%__MODULE__{asn: asn}, fsm), do: {<<asn::32>>, 4, fsm}
end
