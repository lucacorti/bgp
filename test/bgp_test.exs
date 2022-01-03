defmodule BGPTest do
  use ExUnit.Case
  doctest BGP

  alias BGP.Message.{KeepAlive, Notification, Open, Update}

  test "KEEPALIVE encode and decode" do
    assert {:ok, %KeepAlive{}} =
             %KeepAlive{}
             |> BGP.Message.encode([])
             |> IO.iodata_to_binary()
             |> BGP.Message.decode([])
  end

  test "NOTIFICATION encode and decode" do
    code = :fsm
    subcode = :unspecific
    data = ""

    assert {:ok, %Notification{code: ^code, subcode: ^subcode, data: ^data}} =
             %Notification{code: code, subcode: subcode, data: data}
             |> BGP.Message.encode([])
             |> IO.iodata_to_binary()
             |> BGP.Message.decode([])
  end

  test "OPEN encode and decode" do
    asn = 100
    bgp_id = {127, 0, 0, 1}

    assert {:ok, %Open{asn: ^asn, bgp_id: ^bgp_id, hold_time: 0}} =
             %Open{asn: asn, bgp_id: bgp_id}
             |> BGP.Message.encode([])
             |> IO.iodata_to_binary()
             |> BGP.Message.decode([])
  end

  test "UPDATE encode and decode" do
    w_r = [{127, 0, 0, 1}, {0, 0, 0, 0}]

    assert {:ok, %Update{withdrawn_routes: ^w_r}} =
             %Update{withdrawn_routes: w_r}
             |> BGP.Message.encode([])
             |> IO.iodata_to_binary()
             |> BGP.Message.decode([])
  end
end
