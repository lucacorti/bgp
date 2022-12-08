defmodule BGP.Message.OPEN.Parameter.Capabilities.GracefulRestart do
  @moduledoc false

  alias BGP.Message.{AFN, Encoder, NOTIFICATION}

  @type seconds :: non_neg_integer()
  @type forwarding :: boolean()
  @type af :: {AFN.afi(), AFN.safi(), forwarding()}
  @type t :: %__MODULE__{restarted: boolean(), time: seconds(), afs: [af()]}

  @enforce_keys [:restarted, :time]
  defstruct restarted: nil, time: nil, afs: []

  @behaviour Encoder

  @impl Encoder
  def decode(<<restarted::1, _reserved::3, time::12, rest::binary>>, _fsm),
    do: %__MODULE__{restarted: restarted == 1, time: time, afs: decode_afs(rest, [])}

  def decode(_data, _fsm) do
    raise NOTIFICATION, code: :open_message
  end

  defp decode_afs(<<>>, afs), do: Enum.reverse(afs)

  defp decode_afs(<<afi::16, safi::8, forwarding::1, _reserved::7, rest::binary>>, afs),
    do: decode_afs(rest, [{decode_afi(afi), decode_safi(safi), forwarding == 1} | afs])

  defp decode_afi(afi) do
    case AFN.decode_afi(afi) do
      {:ok, afi} -> afi
      :error -> raise NOTIFICATION, code: :open_message
    end
  end

  defp decode_safi(safi) do
    case AFN.decode_safi(safi) do
      {:ok, safi} -> safi
      :error -> raise NOTIFICATION, code: :open_message
    end
  end

  @impl Encoder
  def encode(_multi_protocol, _fsm), do: {<<>>, 0}
end
