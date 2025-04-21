defmodule BGP.Message.UPDATE.Attribute do
  @moduledoc Module.split(__MODULE__) |> Enum.map_join(" ", &String.capitalize/1)

  alias BGP.Message.{Encoder, NOTIFICATION}

  alias BGP.Message.UPDATE.Attribute.{
    Aggregator,
    AS4Aggregator,
    AS4Path,
    ASPath,
    AtomicAggregate,
    ClusterList,
    Communities,
    ExtendedCommunities,
    IPv6ExtendedCommunities,
    LargeCommunities,
    LocalPref,
    MpReachNLRI,
    MpUnreachNLRI,
    MultiExitDisc,
    NextHop,
    Origin,
    OriginatorId
  }

  attributes = [
    {Origin, 1, :well_known, :mandatory},
    {ASPath, 2, :well_known, :mandatory},
    {NextHop, 3, :well_known, :mandatory},
    {MultiExitDisc, 4, :optional, :non_transitive},
    {LocalPref, 5, :well_known, :discretionary},
    {AtomicAggregate, 6, :well_known, :discretionary},
    {Aggregator, 7, :optional, :transitive},
    {Communities, 8, :optional, :transitive},
    {OriginatorId, 9, :optional, :transitive},
    {ClusterList, 10, :optional, :transitive},
    {MpReachNLRI, 14, :optional, :transitive},
    {MpUnreachNLRI, 15, :optional, :transitive},
    {ExtendedCommunities, 16, :optional, :transitive},
    {AS4Path, 17, :optional, :transitive},
    {AS4Aggregator, 18, :optional, :transitive},
    {IPv6ExtendedCommunities, 25, :optional, :transitive},
    {LargeCommunities, 32, :optional, :transitive}
  ]

  @type value ::
          unquote(
            Enum.map_join(attributes, " | ", &(to_string(elem(&1, 0)) <> ".t()"))
            |> Code.string_to_quoted!()
          )

  @type t :: %__MODULE__{
          optional: 0..1,
          partial: 0..1,
          transitive: 0..1,
          value: value()
        }

  @enforce_keys [:value]
  defstruct optional: 0, partial: 0, transitive: 0, value: nil

  @behaviour Encoder

  @impl Encoder
  def decode(
        <<
          optional::1,
          transitive::1,
          partial::1,
          0::1,
          _unused::4,
          code::8,
          length::8,
          attribute::binary-size(length)
        >> = data,
        session
      ),
      do: decode_attribute(code, optional, partial, transitive, attribute, data, session)

  def decode(
        <<
          optional::1,
          transitive::1,
          partial::1,
          1::1,
          _unused::4,
          code::8,
          length::16,
          attribute::binary-size(length)
        >> = data,
        session
      ),
      do: decode_attribute(code, optional, partial, transitive, attribute, data, session)

  defp decode_attribute(code, optional, partial, transitive, attribute, data, session) do
    case module_for_code(code) do
      {:ok, module} ->
        check_flags(module, optional, transitive, partial, data)

        {value, session} = module.decode(attribute, session)

        {
          %__MODULE__{
            optional: optional,
            partial: partial,
            transitive: transitive,
            value: value
          },
          session
        }

      :error ->
        raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list, data: code
    end
  end

  @impl Encoder
  def encode(%__MODULE__{value: %module{} = value} = attribute, session) do
    case code_for_module(module) do
      {:ok, type} ->
        {data, length, session} = module.encode(value, session)
        extended = if length > 255, do: 1, else: 0
        length_size = 8 + 8 * extended

        {
          [
            <<
              optional(attribute)::1,
              transitive(attribute)::1,
              partial(attribute)::1,
              extended::1,
              0::4
            >>,
            <<type::8>>,
            <<length::size(length_size)>>,
            data
          ],
          2 + div(length_size, 8) + length,
          session
        }

      :error ->
        raise NOTIFICATION,
          code: :update_message,
          subcode: :malformed_attribute_list,
          data: module
    end
  end

  for {module, _code, type, _mode} <- attributes do
    case type do
      :optional ->
        def optional(%__MODULE__{value: %unquote(module){}}), do: 1

      _type ->
        def optional(%__MODULE__{value: %unquote(module){}}), do: 0
    end
  end

  for {module, _code, type, _mode} <- attributes do
    case type do
      :well_known ->
        defp transitive(%__MODULE__{value: %unquote(module){}}), do: 1

      _type ->
        defp transitive(%__MODULE__{transitive: transitive, value: %unquote(module){}}),
          do: transitive
    end
  end

  for {module, _code, type, mode} <- attributes do
    case type do
      type when type == :well_known or (type == :optional and mode == :non_transitive) ->
        defp partial(%__MODULE__{value: %unquote(module){}}), do: 0

      _type ->
        defp partial(%__MODULE__{partial: partial, value: %unquote(module){}}), do: partial
    end
  end

  for {module, _code, type, mode} <- attributes do
    case {type, mode} do
      {:well_known, :mandatory} ->
        defp check_flags(unquote(module), 0 = _optional, 1 = _transitive, 0 = _partial, _data),
          do: :ok

      {:well_known, :discretionary} ->
        defp check_flags(unquote(module), 1 = _optional, 1 = _transitive, _partial, _data),
          do: :ok

      {:optional, :transitive} ->
        defp check_flags(unquote(module), 1 = _optional, 1 = _transitive, _partial, _data),
          do: :ok

      {:optional, :non_transitive} ->
        defp check_flags(
               unquote(module),
               1 = _optional,
               0 = _transitive,
               0 = _partial,
               _data
             ),
             do: :ok
    end
  end

  defp check_flags(_type, _optional, _transitive, _partial, data) do
    raise NOTIFICATION, code: :update_message, subcode: :attribute_flags_error, data: data
  end

  for({module, code, _type, _mode} <- attributes) do
    defp code_for_module(unquote(module)), do: {:ok, unquote(code)}
  end

  defp code_for_module(_module), do: :error

  for {module, code, _type, _mode} <- attributes do
    defp module_for_code(unquote(code)), do: {:ok, unquote(module)}
  end

  defp module_for_code(_code), do: :error
end
