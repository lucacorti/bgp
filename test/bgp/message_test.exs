defmodule BGP.MessageTest do
  use ExUnit.Case

  alias BGP.{FSM, Message}
  alias BGP.Message.{KEEPALIVE, NOTIFICATION, OPEN, UPDATE}
  alias BGP.Message.UPDATE.Attribute
  alias BGP.Message.UPDATE.Attribute.{ASPath, NextHop, Origin}

  import IP.Sigil

  setup_all _ctx do
    %{fsm: FSM.new([asn: 65_000, bgp_id: ~i(1.2.3.4)], hold_time: [seconds: 90])}
  end

  test "KEEPALIVE encode and decode", %{fsm: fsm} do
    assert {iodata, fsm} = Message.encode(%KEEPALIVE{}, fsm)

    assert {%KEEPALIVE{}, _fsm} =
             iodata
             |> IO.iodata_to_binary()
             |> Message.decode(fsm)
  end

  test "NOTIFICATION encode and decode", %{fsm: fsm} do
    code = :fsm
    subcode = :unspecific
    data = <<>>

    assert {iodata, fsm} =
             BGP.Message.encode(%NOTIFICATION{code: code, subcode: subcode, data: data}, fsm)

    assert {%NOTIFICATION{code: ^code, subcode: ^subcode, data: ^data}, _fsm} =
             iodata
             |> IO.iodata_to_binary()
             |> BGP.Message.decode(fsm)
  end

  test "OPEN encode and decode", %{
    fsm: %FSM{asn: asn, bgp_id: bgp_id, hold_time: hold_time} = fsm
  } do
    assert {iodata, fsm} =
             BGP.Message.encode(%OPEN{asn: asn, bgp_id: bgp_id, hold_time: hold_time}, fsm)

    assert {%OPEN{asn: ^asn, bgp_id: ^bgp_id, hold_time: ^hold_time}, _fsm} =
             iodata
             |> IO.iodata_to_binary()
             |> BGP.Message.decode(fsm)
  end

  test "UPDATE encode and decode", %{fsm: %FSM{} = fsm} do
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
      %Attribute{transitive: 1, value: %ASPath{value: [{:as_sequence, 1, [fsm.asn]}]}},
      %Attribute{transitive: 1, value: %NextHop{value: fsm.bgp_id}}
    ]

    assert {iodata, fsm} =
             BGP.Message.encode(
               %UPDATE{withdrawn_routes: withdrawn, path_attributes: attributes, nlri: nlri},
               fsm
             )

    assert {%UPDATE{withdrawn_routes: ^withdrawn, path_attributes: ^attributes, nlri: ^nlri},
            _fsm} =
             iodata
             |> IO.iodata_to_binary()
             |> BGP.Message.decode(fsm)
  end
end
