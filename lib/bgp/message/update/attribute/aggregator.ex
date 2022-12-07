defmodule BGP.Message.UPDATE.Attribute.Aggregator do
  @moduledoc false

  alias BGP.{FSM, Prefix}
  alias BGP.Message.{Encoder, NOTIFICATION}

  @asn_max :math.pow(2, 16) - 1
  @asn_four_octets_max :math.pow(2, 16) - 1

  @type t :: %__MODULE__{asn: BGP.asn(), address: Prefix.t()}

  @enforce_keys [:asn, :address]
  defstruct asn: nil, address: nil

  @behaviour Encoder

  @impl Encoder
  def decode(<<asn::32, prefix::binary-size(4)>>, %FSM{four_octets: true})
      when asn > 0 and asn < @asn_four_octets_max do
    case Prefix.decode(prefix) do
      {:ok, address} ->
        %__MODULE__{asn: asn, address: address}

      :error ->
        raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
    end
  end

  def decode(<<asn::16, prefix::binary-size(4)>>, %FSM{four_octets: false})
      when asn > 0 and asn < @asn_max do
    case Prefix.decode(prefix) do
      {:ok, address} ->
        %__MODULE__{asn: asn, address: address}

      :error ->
        raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
    end
  end

  def decode(_aggregator, _fsm), do: :skip

  @impl Encoder
  def encode(%__MODULE__{asn: asn, address: address}, fsm) do
    asn_length = asn_length(fsm)

    case Prefix.encode(address) do
      {:ok, prefix, 32} ->
        [<<asn::size(asn_length)>>, prefix]

      :error ->
        raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
    end
  end

  def encode(_origin, _fsm) do
    raise NOTIFICATION, code: :update_message, subcode: :malformed_attribute_list
  end

  defp asn_length(%FSM{four_octets: true}), do: 32
  defp asn_length(%FSM{four_octets: false}), do: 16
end
