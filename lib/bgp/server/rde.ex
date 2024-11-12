defmodule BGP.Server.RDE do
  @moduledoc """
  BGP RDE

  Implementation of BGP Route Decision Engine and
  [BGP Decision Process](https://datatracker.ietf.org/doc/html/rfc4271#section-9.1).

  This is a simplified diagram of the state machine showing the most significant events
  and state transitions:

  ```mermaid
  stateDiagram-v2
    [*] --> Idle
    Idle --> Processing : state_timeout
    Processing --> Idle : Processing done
  ```
  """
  @behaviour :gen_statem

  alias BGP.Message.UPDATE
  alias BGP.Message.UPDATE.Attribute
  alias BGP.Server
  alias BGP.Server.RDE.RIB
  alias BGP.Server.Session

  require Logger

  @enforce_keys [:config, :adj_ribs_in, :update_queue]
  defstruct [:config, :adj_ribs_in, :update_queue]

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(args),
    do: :gen_statem.start_link({:local, Server.rde_for(args[:server])}, __MODULE__, args, [])

  @doc false
  def child_spec({args, opts}),
    do: %{id: make_ref(), start: {__MODULE__, :start_link, [{args, opts}]}}

  def child_spec(opts),
    do: %{id: make_ref(), start: {__MODULE__, :start_link, [opts]}}

  @spec queue_update(Server.t(), Session.data(), UPDATE.t()) :: :ok
  def queue_update(server, session, update),
    do: :gen_statem.call(Server.rde_for(server), {:process_update, session, update})

  @impl :gen_statem
  def callback_mode, do: [:handle_event_function, :state_enter]

  @impl :gen_statem
  def init(args) do
    {
      :ok,
      :idle,
      %__MODULE__{
        config: args,
        update_queue: :queue.new(),
        adj_ribs_in: RIB.new(:adj_ribs_in)
      },
      {:state_timeout, 10_000, nil}
    }
  end

  @impl :gen_statem
  def handle_event(:enter, old_state, new_state, _data) do
    Logger.info("#{old_state} -> #{new_state}")
    :keep_state_and_data
  end

  @impl :gen_statem
  def handle_event(
        {:call, from},
        {:queue_update, session, update},
        :idle,
        %__MODULE__{} = data
      ) do
    {
      :keep_state,
      %__MODULE__{data | update_queue: :queue.in({session, update}, data.update_queue)},
      [{:reply, from, :ok}]
    }
  end

  @impl :gen_statem
  def handle_event(:state_timeout, _event, :idle, data) do
    Logger.info("RDE idle timeout")
    {:next_state, :processing, data, {:next_event, :internal, :degree_of_preference}}
  end

  @impl :gen_statem
  def handle_event(:internal, :degree_of_preference, :processing, %__MODULE__{} = data) do
    Logger.info("Calculation of Degree of Preference")

    :queue.fold(
      fn {session, update}, acc ->
        for route <- update.nlri do
          preference = preference(session, update, route)

          RIB.upsert(
            data.adj_ribs_in,
            {{session.bgp_id, route}, preference, update.path_attributes}
          )
        end

        for route <- update.withdrawn_routes do
          RIB.delete(data.adj_ribs_in, {session.bgp_id, route})
        end

        acc
      end,
      :ok,
      data.update_queue
    )

    Logger.info("exiting Phase 1: Calculation of Degree of Preference")

    {
      :keep_state,
      %__MODULE__{data | update_queue: :queue.new()},
      {:next_event, :internal, :route_selection}
    }
  end

  def handle_event(:internal, :route_selection, :processing, data) do
    Logger.info("entering Phase 2: Route Selection")
    Logger.info("exiting Phase 2: Route Selection")

    {
      :keep_state,
      data,
      {:next_event, :internal, :route_dissemination}
    }
  end

  def handle_event(:internal, :route_dissemination, :processing, data) do
    Logger.info("entering Phase 3: Route Dissemination")
    Logger.info("exiting Phase 3: Route Dissemination")

    {:next_state, :idle, data, {:state_timeout, 10_000, nil}}
  end

  defp preference(%Session{ibgp: true} = session, path_attributes, route) do
    Enum.find_value(path_attributes, pib_preference(session, path_attributes, route), fn
      %Attribute{value: %Attribute.LocalPref{value: value}} -> value
      _attribute -> nil
    end)
  end

  defp preference(%Session{ibgp: false} = session, path_attributes, route),
    do: pib_preference(session, path_attributes, route)

  defp pib_preference(_session, _path_attributes, _route), do: 0
end
