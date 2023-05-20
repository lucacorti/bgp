defmodule BGP.Server.RDE do
  @moduledoc """
  RDE implementation based on RFC4271 section 9 (https://www.rfc-editor.org/rfc/rfc4271#section-9):

    * performs preference calculation for received routes.
    * performs route selection and maintains Adj-RIB-In, Loc-Rib, Adjs-RIB-Out in ETS.
    * performs route dissemination to peers after processing updates.

  """

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
