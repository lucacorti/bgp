defmodule BGP.Message.OPEN.Parameter.Capabilities.GracefulRestart do
  @moduledoc false

  alias BGP.AFN
  alias BGP.Message.{Encoder, NOTIFICATION}

  @type seconds :: non_neg_integer()
  @type forwarding :: boolean()
  @type af :: {AFN.afi(), AFN.safi(), forwarding()}
  @type t :: %__MODULE__{restarted: boolean(), time: seconds(), afs: [af()]}

  @enforce_keys [:restarted, :time]
  defstruct restarted: nil, time: nil, afs: []

  @behaviour Encoder

  @impl Encoder
  def decode(<<restarted::1, _reserved::3, time::12, rest::binary>>, _options),
    do: %__MODULE__{restarted: restarted == 1, time: time, afs: decode_afs(rest, [])}

  def decode(_data, _options) do
    raise NOTIFICATION, code: :open_message
  end

  defp decode_afs(<<>>, afs), do: Enum.reverse(afs)

  defp decode_afs(<<afi::16, safi::8, forwarding::1, _reserved::7, rest::binary>>, afs),
    do: decode_afs(rest, [{AFN.decode_afi(afi), AFN.decode_safi(safi), forwarding == 1} | afs])

  @impl Encoder
  def encode(_multi_protocol, _options), do: []
end
