defmodule BGP.Server.RDE do
  @moduledoc false

  alias BGP.{Message.UPDATE, Server}

  use GenServer

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(args),
    do: GenServer.start_link(__MODULE__, args, name: Server.rde_for(args[:server]))

  @spec process_update(Server.t(), UPDATE.t()) :: :ok
  def process_update(server, update),
    do: GenServer.call(Server.rde_for(server), {:process_update, update})

  @impl GenServer
  def init(_args) do
    {:ok, %{rib: MapSet.new(), rib_in: MapSet.new(), rib_out: MapSet.new()}}
  end

  @impl GenServer
  def handle_call({:process_update, %UPDATE{}}, _from, state) do
    {:reply, :ok, state}
  end
end
