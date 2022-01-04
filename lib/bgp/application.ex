defmodule BGP.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {BGP.Session,
       [asn: 65_000, bgp_id: "192.168.24.1", connect_retry: [secs: 5], host: "192.168.64.2"]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: BGP.Supervisor)
  end
end
