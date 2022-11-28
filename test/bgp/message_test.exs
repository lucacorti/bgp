defmodule BGP.MessageTest do
  use ExUnit.Case

  alias BGP.Message.{KEEPALIVE, NOTIFICATION, OPEN, UPDATE}

  test "KEEPALIVE encode and decode" do
    assert %KEEPALIVE{} =
             %KEEPALIVE{}
             |> BGP.Message.encode([])
             |> IO.iodata_to_binary()
             |> BGP.Message.decode([])
  end

  test "NOTIFICATION encode and decode" do
    code = :fsm
    subcode = :unspecific
    data = <<>>

    assert %NOTIFICATION{code: ^code, subcode: ^subcode, data: ^data} =
             %NOTIFICATION{code: code, subcode: subcode, data: data}
             |> BGP.Message.encode([])
             |> IO.iodata_to_binary()
             |> BGP.Message.decode([])
  end

  test "OPEN encode and decode" do
    asn = 100
    bgp_id = {127, 0, 0, 1}
    hold_time = 90

    assert %OPEN{asn: ^asn, bgp_id: ^bgp_id, hold_time: ^hold_time} =
             %OPEN{asn: asn, bgp_id: bgp_id, hold_time: hold_time}
             |> BGP.Message.encode([])
             |> IO.iodata_to_binary()
             |> BGP.Message.decode([])
  end

  test "UPDATE encode and decode" do
    w_r = [{127, 0, 0, 1}, {0, 0, 0, 0}]

    assert %UPDATE{withdrawn_routes: ^w_r} =
             %UPDATE{withdrawn_routes: w_r}
             |> BGP.Message.encode([])
             |> IO.iodata_to_binary()
             |> BGP.Message.decode([])
  end
end
