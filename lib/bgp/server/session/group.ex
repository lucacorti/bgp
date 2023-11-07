defmodule BGP.Server.Session.Group do
  @moduledoc false

  alias BGP.Server

  @typedoc "Server Session Scope"
  @type scope :: module()

  @typedoc "Server Session Group"
  @type group :: atom()

  @doc false
  def child_spec(server) do
    %{
      id: Server.session_group_for(server),
      start: {__MODULE__, :start_link, [server]}
    }
  end

  @spec start_link(Server.t()) :: {:ok, pid()} | {:error, any()}
  def start_link(server) do
    :pg.start_link(Server.session_group_for(server))
  end

  @spec join(Server.t(), group()) :: :ok
  def join(server, group),
    do: :pg.join(Server.session_group_for(server), group, self())

  @spec leave(Server.t(), group()) :: :ok | :not_joined
  def leave(server, group),
    do: :pg.leave(Server.session_group_for(server), group, self())

  @spec monitor(Server.t()) :: {reference(), [pid()]}
  def monitor(server) do
    :pg.monitor_scope(Server.session_group_for(server))
  end
end
