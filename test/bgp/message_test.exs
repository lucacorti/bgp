defmodule BGP.MessageTest do
  use ExUnit.Case

  alias BGP.FSM
  alias BGP.Message.{KEEPALIVE, NOTIFICATION, OPEN, UPDATE}

  import IP.Sigil

  setup_all _ctx do
    %{fsm: FSM.new([asn: 65_000, bgp_id: {192, 168, 1, 1}], [])}
  end

  test "KEEPALIVE encode and decode", %{fsm: fsm} do
    assert %KEEPALIVE{} =
             %KEEPALIVE{}
             |> BGP.Message.encode(fsm)
             |> IO.iodata_to_binary()
             |> BGP.Message.decode(fsm)
  end

  test "NOTIFICATION encode and decode", %{fsm: fsm} do
    code = :fsm
    subcode = :unspecific
    data = <<>>

    assert %NOTIFICATION{code: ^code, subcode: ^subcode, data: ^data} =
             %NOTIFICATION{code: code, subcode: subcode, data: data}
             |> BGP.Message.encode(fsm)
             |> IO.iodata_to_binary()
             |> BGP.Message.decode(fsm)
  end

  test "OPEN encode and decode", %{fsm: fsm} do
    asn = 100
    bgp_id = ~i(127.0.0.1)
    hold_time = 90

    assert %OPEN{asn: ^asn, bgp_id: ^bgp_id, hold_time: ^hold_time} =
             %OPEN{asn: asn, bgp_id: bgp_id, hold_time: hold_time}
             |> BGP.Message.encode(fsm)
             |> IO.iodata_to_binary()
             |> BGP.Message.decode(fsm)
  end

  test "UPDATE encode and decode", %{fsm: fsm} do
    prefixes = [
      ~i(0.0.0.0/0),
      ~i(1.0.0.0/8),
      ~i(2.16.0.0/12),
      ~i(3.4.0.0/16),
      ~i(4.5.16.0/20),
      ~i(4.6.20.0/22),
      ~i(5.6.7.0/24),
      ~i(6.7.8.16/28),
      ~i(7.8.9.8/29),
      ~i(8.9.10.20/32)
    ]

    assert %UPDATE{withdrawn_routes: ^prefixes, nlri: ^prefixes} =
             %UPDATE{withdrawn_routes: prefixes, nlri: prefixes}
             |> BGP.Message.encode(fsm)
             |> IO.iodata_to_binary()
             |> BGP.Message.decode(fsm)
  end
end
