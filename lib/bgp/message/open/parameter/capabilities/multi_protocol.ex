defmodule BGP.Message.OPEN.Parameter.Capabilities.MultiProtocol do
  @moduledoc false

  alias BGP.AFN
  alias BGP.Message.{Encoder, NOTIFICATION}

  @type t :: %__MODULE__{afi: AFN.afi(), safi: AFN.safi()}
  @enforce_keys [:afi, :safi]
  defstruct afi: nil, safi: nil

  alias BGP.Message.Encoder

  @behaviour Encoder

  @impl Encoder
  def decode(<<afi::16, _reserved::8, safi::8>>, _options),
    do: %__MODULE__{afi: AFN.decode_afi(afi), safi: AFN.decode_safi(safi)}

  def decode(_data, _options) do
    raise NOTIFICATION, code: :open_message
  end

  @impl Encoder
  def encode(%__MODULE__{afi: afi, safi: safi}, _options),
    do: [<<AFN.encode_afi(afi)::16>>, <<0::8>>, <<AFN.encode_safi(safi)::8>>]

  def encode(_data, _options) do
    raise NOTIFICATION, code: :open_message
  end
end
