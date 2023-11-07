defmodule BGP.Server.RDE do
  @moduledoc """
  RDE implementation based on RFC4271 section 9 (https://www.rfc-editor.org/rfc/rfc4271#section-9):

    * performs preference calculation for received routes.
    * performs route selection and maintains Adj-RIB-In, Loc-Rib, Adjs-RIB-Out in ETS.
    * performs route dissemination to peers after processing updates.

  ```mermaid
  stateDiagram-v2
    [*] --> Idle
    Idle --> Processing : state_timeout
    Idle --> Processing : calculate
    Processing --> Idle : route_dissemination
    Processing --> Idle
  ```
  """

  # TODO
  # implement handle info for monitor
  # {Ref, join, Group, [JoinPid1, JoinPid2]}

  @behaviour :gen_statem

  alias BGP.{Message.UPDATE, Server}
  alias BGP.Server.Session.Group

  require Logger

  @doc false
  def child_spec(server),
    do: %{id: Server.rde_for(server), start: {__MODULE__, :start_link, [server]}}

  @spec process_update(Server.t(), UPDATE.t()) :: :ok
  def process_update(server, update),
    do: :gen_statem.call(Server.rde_for(server), {:process_update, update})

  @spec start_link(term()) :: :gen_statem.start_ret()
  def start_link(server) do
    :gen_statem.start_link({:local, Server.rde_for(server)}, __MODULE__, [server],
      debug: [:trace]
    )
  end

  @impl :gen_statem
  def callback_mode, do: [:handle_event_function, :state_enter]

  @impl :gen_statem
  def init([server]) do
    Group.monitor(server)

    data = %{}
    actions = [{:next_event, :internal, :accept_updates}]

    {:ok, :idle, data, actions}
  end

  @impl :gen_statem
  def handle_event(:enter, old_state, new_state, data) do
    Logger.debug("RDE #{data}: #{old_state} -> #{new_state}")
    :keep_state_and_data
  end

  def handle_event(:internal, :accept_updates, :idle, _data) do
    {
      :keep_state_and_data,
      [{:state_timeout, 1_000}]
    }
  end

  def handle_event(:state_timeout, _, :idle, data) do
    {
      :next_state,
      :processing,
      data,
      [{:next_event, :internal, :calculate}]
    }
  end

  def handle_event(:internal, :calculate, :processing, data) do
    # TODO implementation
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, :route_dissemination}
      ]
    }
  end

  def handle_event(:internal, :route_dissemination, :idle, _data) do
    # TODO implementation
    :keep_state_and_data
  end

  # @spec start_link(Keyword.t()) :: GenServer.on_start()
  # def start_link(args),
  #   do: GenServer.start_link(__MODULE__, args, name: Server.rde_for(args[:server]))

  # @impl GenServer
  # def init(_args) do
  #   {:ok, %{rib: MapSet.new(), rib_in: MapSet.new(), rib_out: MapSet.new()}}
  # end

  # @impl GenServer
  # def handle_call({:process_update, %UPDATE{}}, _from, state) do
  #   {:reply, :ok, state}
  # end
end
