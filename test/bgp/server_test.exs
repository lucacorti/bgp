defmodule BGP.ServerTest do
  use ExUnit.Case, async: true

  setup_all _ctx do
    %{
      server_a: start_link_supervised!({BGP.Server, BGP.TestServerA}),
      server_b: start_link_supervised!({BGP.Server, BGP.TestServerB})
    }
  end
end
