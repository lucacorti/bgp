defmodule BGP.MessageTest do
  use ExUnit.Case

  alias BGP.FSM
  alias BGP.Message.{KEEPALIVE, NOTIFICATION, OPEN, UPDATE}

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
    bgp_id = {127, 0, 0, 1}
    hold_time = 90

    assert %OPEN{asn: ^asn, bgp_id: ^bgp_id, hold_time: ^hold_time} =
             %OPEN{asn: asn, bgp_id: bgp_id, hold_time: hold_time}
             |> BGP.Message.encode(fsm)
             |> IO.iodata_to_binary()
             |> BGP.Message.decode(fsm)
  end

  test "UPDATE encode and decode", %{fsm: fsm} do
    prefixes = [
      {0, {0, 0, 0, 0}},
      {8, {1, 0, 0, 0}},
      {12, {2, 0, 0, 0}},
      {16, {3, 0, 0, 0}},
      {20, {4, 0, 0, 0}},
      {24, {5, 0, 0, 0}},
      {28, {6, 0, 0, 0}},
      {29, {7, 0, 0, 0}},
      {32, {8, 0, 0, 0}}
    ]

    assert %UPDATE{withdrawn_routes: ^prefixes, nlri: ^prefixes} =
             %UPDATE{withdrawn_routes: prefixes, nlri: prefixes}
             |> BGP.Message.encode(fsm)
             |> IO.iodata_to_binary()
             |> BGP.Message.decode(fsm)
  end
end
