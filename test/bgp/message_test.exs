defmodule BGP.MessageTest do
  use ExUnit.Case

  alias BGP.Message
  alias BGP.Message.{KEEPALIVE, NOTIFICATION, OPEN, UPDATE}
  alias BGP.Message.OPEN.Capabilities
  alias BGP.Message.UPDATE.Attribute
  alias BGP.Message.UPDATE.Attribute.{ASPath, NextHop, Origin}
  alias BGP.Server.Session

  import IP.Sigil

  setup_all _ctx do
    %{
      session: %Session{
        asn: 65_000,
        bgp_id: ~i(1.2.3.4),
        host: ~i(1.2.3.4),
        mode: :passive,
        notification_without_open: true,
        port: 179,
        start: :manual,
        server: nil,
        transport: BGP.Server.Session.Transport.TCP,
        transport_opts: []
      }
    }
  end

  test "KEEPALIVE encode and decode", %{session: session} do
    assert %KEEPALIVE{} =
             Message.encode(%KEEPALIVE{}, session)
             |> IO.iodata_to_binary()
             |> Message.decode(session)
  end

  test "NOTIFICATION encode and decode", %{session: session} do
    code = :fsm
    subcode = :unspecific
    data = <<>>

    assert %NOTIFICATION{code: ^code, subcode: ^subcode, data: ^data} =
             Message.encode(%NOTIFICATION{code: code, subcode: subcode, data: data}, session)
             |> IO.iodata_to_binary()
             |> Message.decode(session)
  end

  test "OPEN encode and decode", %{
    session: %Session{asn: asn, bgp_id: bgp_id} = session
  } do
    hold_time = 90
    capabilities = %Capabilities{}

    assert %OPEN{asn: ^asn, bgp_id: ^bgp_id, hold_time: ^hold_time} =
             Message.encode(
               %OPEN{asn: asn, bgp_id: bgp_id, hold_time: hold_time, capabilities: capabilities},
               session
             )
             |> IO.iodata_to_binary()
             |> Message.decode(session)
  end

  test "OPEN decode returns capabilities without touching the session", %{
    session: %Session{asn: asn, bgp_id: bgp_id} = session
  } do
    capabilities = %Capabilities{four_octets_asn: true, extended_message: true}

    assert %OPEN{capabilities: %Capabilities{four_octets_asn: true, extended_message: true}} =
             Message.encode(
               %OPEN{asn: asn, bgp_id: bgp_id, hold_time: 90, capabilities: capabilities},
               session
             )
             |> IO.iodata_to_binary()
             |> Message.decode(session)

    refute session.four_octets
    refute session.extended_message
  end

  test "UPDATE encode and decode", %{session: %Session{} = session} do
    nlri = [
      ~i(0.0.0.0/0),
      ~i(1.0.0.0/8),
      ~i(2.16.0.0/12),
      ~i(3.4.0.0/16),
      ~i(4.5.16.0/20)
    ]

    withdrawn = [
      ~i(4.6.20.0/22),
      ~i(5.6.7.0/24),
      ~i(6.7.8.16/28),
      ~i(7.8.9.8/29),
      ~i(8.9.10.20/32)
    ]

    attributes = [
      %Attribute{transitive: 1, value: %Origin{value: 0}},
      %Attribute{transitive: 1, value: %ASPath{value: [{:as_sequence, 1, [session.asn]}]}},
      %Attribute{transitive: 1, value: %NextHop{value: session.bgp_id}}
    ]

    assert %UPDATE{} =
             update =
             Message.encode(
               %UPDATE{withdrawn_routes: withdrawn, path_attributes: attributes, nlri: nlri},
               session
             )
             |> IO.iodata_to_binary()
             |> Message.decode(session)

    assert update.withdrawn_routes == withdrawn
    assert update.path_attributes == attributes
    assert update.nlri == nlri
  end
end
