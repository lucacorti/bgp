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
        server: nil
      }
    }
  end

  test "KEEPALIVE encode and decode", %{session: session} do
    assert {iodata, session} = Message.encode(%KEEPALIVE{}, session)

    assert {%KEEPALIVE{}, _session} =
             iodata
             |> IO.iodata_to_binary()
             |> Message.decode(session)
  end

  test "NOTIFICATION encode and decode", %{session: session} do
    code = :session
    subcode = :unspecific
    data = <<>>

    assert {iodata, session} =
             BGP.Message.encode(%NOTIFICATION{code: code, subcode: subcode, data: data}, session)

    assert {%NOTIFICATION{code: ^code, subcode: ^subcode, data: ^data}, _session} =
             iodata
             |> IO.iodata_to_binary()
             |> BGP.Message.decode(session)
  end

  test "OPEN encode and decode", %{
    session: %Session{asn: asn, bgp_id: bgp_id} = session
  } do
    hold_time = 90
    capabilities = %Capabilities{}

    assert {iodata, session} =
             BGP.Message.encode(
               %OPEN{asn: asn, bgp_id: bgp_id, hold_time: hold_time, capabilities: capabilities},
               session
             )

    assert {%OPEN{asn: ^asn, bgp_id: ^bgp_id, hold_time: ^hold_time}, _session} =
             iodata
             |> IO.iodata_to_binary()
             |> BGP.Message.decode(session)
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
      %Attribute{transitive: 1, value: %Origin{origin: :igp}},
      %Attribute{transitive: 1, value: %ASPath{value: [{:as_sequence, 1, [session.asn]}]}},
      %Attribute{transitive: 1, value: %NextHop{value: session.bgp_id}}
    ]

    assert {iodata, session} =
             BGP.Message.encode(
               %UPDATE{withdrawn_routes: withdrawn, path_attributes: attributes, nlri: nlri},
               session
             )

    assert {%UPDATE{} = update, _session} =
             iodata
             |> IO.iodata_to_binary()
             |> BGP.Message.decode(session)

    assert update.withdrawn_routes == withdrawn
    assert update.path_attributes == attributes
    assert update.nlri == nlri
  end
end
