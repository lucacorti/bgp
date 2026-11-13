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
  alias BGP.Server
  alias BGP.Server.RDE.{Decision, RIB, Route}
  alias BGP.Server.Session

  require Logger

  @enforce_keys [:config, :adj_ribs_in, :loc_rib, :update_queue]
  defstruct [:config, :adj_ribs_in, :loc_rib, :update_queue, monitors: %{}]

  @doc """
  Starts the RDE.

  Options:
    * `:server` - the `BGP.Server` the RDE belongs to.
    * `:asn` - the server Autonomous System Number.
    * `:interval` - interval between Decision Process runs, in milliseconds.
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(args),
    do: :gen_statem.start_link({:local, Server.rde_for(args[:server])}, __MODULE__, args, [])

  @doc false
  def child_spec({args, opts}),
    do: %{id: make_ref(), start: {__MODULE__, :start_link, [{args, opts}]}}

  def child_spec(opts),
    do: %{id: make_ref(), start: {__MODULE__, :start_link, [opts]}}

  # Sessions only ever cast to the RDE: the RDE calls sessions during Route Dissemination,
  # so a session calling the RDE could deadlock. Peer events share the UPDATE queue so they
  # are applied in the order sessions sent them.

  @doc """
  Queues an UPDATE received by `session` for the next Decision Process run.

  Must be called from the session process: the RDE monitors the caller and withdraws
  all routes received from it if the process exits.
  """
  @spec queue_update(Server.t(), Session.data(), UPDATE.t()) :: :ok
  def queue_update(server, session, update),
    do: :gen_statem.cast(Server.rde_for(server), {:queue_update, self(), session, update})

  @doc """
  Notifies the RDE that the session with peer `host` is no longer established, so all
  routes received from it are withdrawn.

  Session process exits are detected by the RDE itself, this is needed when the
  session goes down but the session process keeps running.
  """
  @spec peer_down(Server.t(), IP.Address.t()) :: :ok
  def peer_down(server, host),
    do: :gen_statem.cast(Server.rde_for(server), {:peer_down, host})

  @impl :gen_statem
  def callback_mode, do: [:handle_event_function, :state_enter]

  @impl :gen_statem
  def init(args) do
    {
      :ok,
      :idle,
      %__MODULE__{
        config: [server: args[:server], asn: args[:asn], interval: args[:interval]],
        update_queue: :queue.new(),
        adj_ribs_in: RIB.new(:adj_ribs_in),
        loc_rib: RIB.new(:loc_rib)
      },
      {:state_timeout, args[:interval], nil}
    }
  end

  @impl :gen_statem
  def handle_event(:enter, old_state, new_state, %__MODULE__{} = data) do
    Logger.info("#{data.config[:server]}: #{old_state} -> #{new_state}")
    :keep_state_and_data
  end

  @impl :gen_statem
  def handle_event(:cast, {:queue_update, pid, session, update}, :idle, %__MODULE__{} = data) do
    data =
      data
      |> monitor_session(pid, session.host)
      |> queue_event({:update, session, update})

    {:keep_state, data}
  end

  @impl :gen_statem
  def handle_event(:cast, {:peer_down, host}, :idle, %__MODULE__{} = data),
    do: {:keep_state, queue_event(data, {:peer_down, host})}

  @impl :gen_statem
  def handle_event(:info, {:DOWN, _ref, :process, pid, _reason}, :idle, %__MODULE__{} = data) do
    case Map.pop(data.monitors, pid) do
      {nil, _monitors} ->
        :keep_state_and_data

      {host, monitors} ->
        Logger.info("#{data.config[:server]}: session process for #{host} exited")
        {:keep_state, queue_event(%__MODULE__{data | monitors: monitors}, {:peer_down, host})}
    end
  end

  @impl :gen_statem
  def handle_event(type, _event, :processing, _data) when type in [:cast, :info],
    do: {:keep_state_and_data, :postpone}

  @impl :gen_statem
  def handle_event(:state_timeout, _event, :idle, %__MODULE__{} = data) do
    Logger.info("#{data.config[:server]}: RDE idle timeout")
    {:next_state, :processing, data, {:next_event, :internal, :degree_of_preference}}
  end

  @impl :gen_statem
  def handle_event(:internal, :degree_of_preference, :processing, %__MODULE__{} = data) do
    if :queue.len(data.update_queue) > 0 do
      {:keep_state, degree_of_preference(data), {:next_event, :internal, :route_selection}}
    else
      Logger.info("#{data.config[:server]}: skipping Decision process: no peer events received")
      {:next_state, :idle, data, {:state_timeout, data.config[:interval], nil}}
    end
  end

  @impl :gen_statem
  def handle_event(:internal, :route_selection, :processing, %__MODULE__{} = data),
    do: {:keep_state, route_selection(data), {:next_event, :internal, :route_dissemination}}

  @impl :gen_statem
  def handle_event(:internal, :route_dissemination, :processing, data),
    do:
      {:next_state, :idle, route_dissemination(data),
       {:state_timeout, data.config[:interval], nil}}

  # Monitoring when the first UPDATE is received guarantees the :DOWN message is
  # received after all UPDATEs sent by the session process.
  defp monitor_session(%__MODULE__{} = data, pid, host) do
    if Map.has_key?(data.monitors, pid) do
      data
    else
      Process.monitor(pid)
      %__MODULE__{data | monitors: Map.put(data.monitors, pid, host)}
    end
  end

  defp queue_event(%__MODULE__{} = data, event),
    do: %__MODULE__{data | update_queue: :queue.in(event, data.update_queue)}

  defp degree_of_preference(%__MODULE__{} = data) do
    Logger.info("#{data.config[:server]}: entering Phase 1: Calculation of Degree of Preference")

    :queue.fold(
      fn
        {:update, %Session{} = session, %UPDATE{} = update}, :ok ->
          for prefix <- update.nlri do
            route = Route.new(session, prefix, update.path_attributes)
            RIB.upsert(data.adj_ribs_in, {{session.host, prefix}, preference(session, route)})
          end

          for prefix <- update.withdrawn_routes do
            RIB.delete(data.adj_ribs_in, {session.host, prefix})
          end

          :ok

        {:peer_down, host}, :ok ->
          RIB.match_delete(data.adj_ribs_in, {{host, :_}, :_})
          :ok
      end,
      :ok,
      data.update_queue
    )

    Logger.info("#{data.config[:server]}: exiting Phase 1: Calculation of Degree of Preference")

    %__MODULE__{data | update_queue: :queue.new()}
  end

  defp preference(%Session{ibgp: true}, %Route{local_pref: local_pref} = route)
       when is_integer(local_pref),
       do: %{route | preference: local_pref}

  defp preference(%Session{} = session, %Route{} = route),
    do: %{route | preference: pib_preference(session, route)}

  defp pib_preference(_session, _route), do: 0

  defp route_selection(%__MODULE__{} = data) do
    Logger.info("#{data.config[:server]}: entering Phase 2: Route Selection")

    candidates =
      RIB.reduce(data.adj_ribs_in, %{}, fn {_key, %Route{} = route}, candidates ->
        if Decision.feasible?(route, data.config[:asn]) do
          Map.update(candidates, route.prefix, [route], &[route | &1])
        else
          candidates
        end
      end)

    for {prefix, routes} <- candidates do
      RIB.upsert(data.loc_rib, {prefix, Decision.select(routes)})
    end

    # Prefixes without feasible routes left are no longer reachable.
    for {prefix, _route} <- RIB.dump(data.loc_rib), not Map.has_key?(candidates, prefix) do
      RIB.delete(data.loc_rib, prefix)
    end

    Logger.info("#{data.config[:server]}: exiting Phase 2: Route Selection")

    data
  end

  defp route_dissemination(%__MODULE__{} = data) do
    Logger.info("#{data.config[:server]}: entering Phase 3: Route Dissemination")

    for {_host, session, _value} <- Server.active_sessions(data.config[:server]) do
      Session.disseminate(session, data.loc_rib)
    end

    Logger.info("#{data.config[:server]}: exiting Phase 3: Route Dissemination")

    data
  end
end
