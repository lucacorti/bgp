defmodule BGP.Server.Session.Supervisor do
  @moduledoc false

  use Supervisor

  alias BGP.Server
  alias BGP.Server.Session

  @doc false
  def child_spec(server),
    do: %{id: server, type: :supervisor, start: {__MODULE__, :start_link, [server]}}

  @spec start_link(Server.t()) :: Supervisor.on_start()
  def start_link(server),
    do: Supervisor.start_link(__MODULE__, server, name: Server.session_supervisor(server))

  @spec start_child(Supervisor.supervisor(), Server.peer_options()) :: Supervisor.on_start_child()
  def start_child(supervisor, peer_options),
    do: Supervisor.start_child(supervisor, Session.child_spec({peer_options, []}))

  @impl Supervisor
  def init(server) do
    children =
      Server.get_config(server)
      |> Keyword.fetch!(:peers)
      |> Enum.map(&{Session, &1})

    Supervisor.init(children, strategy: :one_for_one)
  end
end
