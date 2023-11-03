defmodule BGP.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Mix.env() == :dev do
        [{BGP.Server, BGP.MyServer}]
      else
        []
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: BGP.Supervisor)
  end
end
