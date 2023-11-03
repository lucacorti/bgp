defmodule BGP.Server.Session.Supervisor do
  @moduledoc false

  use Supervisor

  alias BGP.Server

  @doc false
  def child_spec(server),
    do: %{id: server, type: :supervisor, start: {__MODULE__, :start_link, [server]}}

  @spec start_link(Server.t()) :: Supervisor.on_start()
  def start_link(server),
    do: Supervisor.start_link(__MODULE__, server, name: Module.concat(server, Session.Supervisor))

  @impl Supervisor
  def init(server) do
    children =
      Server.get_config(server)
      |> Keyword.fetch!(:peers)
      |> Enum.map(&{BGP.Server.Session, &1})

    Supervisor.init(children, strategy: :one_for_one)
  end
end
