defmodule BGPTest do
  use ExUnit.Case
  doctest BGP

  alias BGP.Message.{KEEPALIVE, NOTIFICATION, OPEN, UPDATE}

  test "KEEPALIVE encode and decode" do
    assert {:ok, %KEEPALIVE{}} =
             %KEEPALIVE{}
             |> BGP.Message.encode([])
             |> IO.iodata_to_binary()
             |> BGP.Message.decode([])
  end

  test "NOTIFICATION encode and decode" do
    code = :fsm
    subcode = :unspecific
    data = <<>>

    assert {:ok, %NOTIFICATION{code: ^code, subcode: ^subcode, data: ^data}} =
             %NOTIFICATION{code: code, subcode: subcode, data: data}
             |> BGP.Message.encode([])
             |> IO.iodata_to_binary()
             |> BGP.Message.decode([])
  end

  test "OPEN encode and decode" do
    asn = 100
    bgp_id = {127, 0, 0, 1}

    assert {:ok, %OPEN{asn: ^asn, bgp_id: ^bgp_id, hold_time: 0}} =
             %OPEN{asn: asn, bgp_id: bgp_id}
             |> BGP.Message.encode([])
             |> IO.iodata_to_binary()
             |> BGP.Message.decode([])
  end

  test "UPDATE encode and decode" do
    w_r = [{127, 0, 0, 1}, {0, 0, 0, 0}]

    assert {:ok, %UPDATE{withdrawn_routes: ^w_r}} =
             %UPDATE{withdrawn_routes: w_r}
             |> BGP.Message.encode([])
             |> IO.iodata_to_binary()
             |> BGP.Message.decode([])
  end
end
