defmodule BGP.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = []

    children =
      if Mix.env() == :dev do
        children ++ [{BGP.Server, server: BGP.MyServer}]
      else
        children
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: BGP.Supervisor)
  end
end
