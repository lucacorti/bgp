defmodule BGP.Message.UPDATE.Attribute do
  @moduledoc false

  alias BGP.Message.{Encoder, NOTIFICATION}

  alias BGP.Message.UPDATE.Attribute.{
    Aggregator,
    AS4Aggregator,
    AS4Path,
    ASPath,
    AtomicAggregate,
    ClusterList,
    Communities,
    LargeCommunities,
    LocalPref,
    MpReachNLRI,
    MpUnreachNLRI,
    MultiExitDisc,
    NextHop,
    Origin,
    OriginatorId
  }

  @behaviour Encoder

  @impl Encoder
  def decode(<<code::8, data::binary>>, fsm),
    do: module_for_type(code).decode(data, fsm)

  @impl Encoder
  def encode(%module{} = message, fsm) do
    {data, length} = module.encode(message, fsm)

    {
      [<<length::16>>, <<type_for_module(module)::8>>, data],
      3 + length
    }
  end

  attributes = [
    {Origin, 1},
    {ASPath, 2},
    {NextHop, 3},
    {MultiExitDisc, 4},
    {LocalPref, 5},
    {AtomicAggregate, 6},
    {Aggregator, 7},
    {Communities, 8},
    {OriginatorId, 9},
    {ClusterList, 10},
    {MpReachNLRI, 14},
    {MpUnreachNLRI, 15},
    {ExtendedCommunities, 16},
    {AS4Path, 17},
    {AS4Aggregator, 18},
    {IPV6ExtendedCommunities, 25},
    {LargeCommunities, 32}
  ]

  for {module, code} <- attributes do
    defp type_for_module(unquote(module)), do: unquote(code)
  end

  defp type_for_module(_module) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end

  for {module, code} <- attributes do
    defp module_for_type(unquote(code)), do: unquote(module)
  end

  defp module_for_type(_code) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end
end
