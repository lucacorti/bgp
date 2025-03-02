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

  @enforce_keys [:config, :adj_ribs_in, :adj_ribs_out, :loc_rib, :update_queue]
  defstruct [:config, :adj_ribs_in, :adj_ribs_out, :loc_rib, :update_queue]

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
    do: :gen_statem.call(Server.rde_for(server), {:queue_update, session, update})

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
        adj_ribs_in: RIB.new(:adj_ribs_in),
        adj_ribs_out: RIB.new(:adj_ribs_out),
        loc_rib: RIB.new(:loc_rib)
      },
      {:state_timeout, 10_000, nil}
    }
  end

  @impl :gen_statem
  def handle_event(:enter, old_state, new_state, %__MODULE__{} = data) do
    Logger.info("#{data.config[:server]}: #{old_state} -> #{new_state}")
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
  def handle_event(:state_timeout, _event, :idle, %__MODULE__{} = data) do
    Logger.info("#{data.config[:server]}: RDE idle timeout")
    {:next_state, :processing, data, {:next_event, :internal, :degree_of_preference}}
  end

  @impl :gen_statem
  def handle_event(:internal, :degree_of_preference, :processing, %__MODULE__{} = data) do
    if :queue.len(data.update_queue) > 0 do
      {:keep_state, degree_of_preference(data), {:next_event, :internal, :route_selection}}
    else
      Logger.info("#{data.config[:server]}: skipping Decision process: No UPDATEs received ")
      {:next_state, :idle, data, {:state_timeout, 10_000, nil}}
    end
  end

  def handle_event(:internal, :route_selection, :processing, %__MODULE__{} = data),
    do: {:keep_state, route_selection(data), {:next_event, :internal, :route_dissemination}}

  def handle_event(:internal, :route_dissemination, :processing, data),
    do: {:next_state, :idle, route_dissemination(data), {:state_timeout, 10_000, nil}}

  defp degree_of_preference(%__MODULE__{} = data) do
    Logger.info("#{data.config[:server]}: entering Phase 1: Calculation of Degree of Preference")

    :queue.fold(
      fn {session, update}, :ok ->
        for prefix <- update.nlri do
          with {:ok, preference} <- preference(session, update, prefix) do
            RIB.upsert(
              data.adj_ribs_in,
              {{session.bgp_id, prefix}, preference, update.path_attributes}
            )
          end
        end

        for prefix <- update.withdrawn_routes do
          RIB.delete(data.adj_ribs_in, {session.bgp_id, prefix})
        end

        :ok
      end,
      :ok,
      data.update_queue
    )

    Logger.info("#{data.config[:server]}: exiting Phase 1: Calculation of Degree of Preference")

    %__MODULE__{data | update_queue: :queue.new()}
  end

  defp preference(%Session{ibgp: true} = session, path_attributes, route) do
    with {:ok, preference} <- pib_preference(session, path_attributes, route) do
      {
        :ok,
        Enum.find_value(path_attributes, preference, fn
          %Attribute{value: %Attribute.LocalPref{value: value}} -> value
          _attribute -> nil
        end)
      }
    end
  end

  defp preference(%Session{ibgp: false} = session, path_attributes, route),
    do: pib_preference(session, path_attributes, route)

  defp pib_preference(_session, _path_attributes, _route), do: {:ok, 0}

  defp route_selection(%__MODULE__{} = data) do
    Logger.info("#{data.config[:server]}: entering Phase 2: Route Selection")

    entries =
      RIB.reduce(
        data.adj_ribs_in,
        %{},
        fn {{_bgp_id, prefix}, _preference, path_attributes} = entry, routes ->
          if prefix_feasible?(path_attributes) do
            Map.update(routes, prefix, entry, &select_prefix(entry, &1))
          else
            routes
          end
        end
      )

    for {prefix, {_key, _preference, path_attributes}} <- entries do
      RIB.upsert(
        data.loc_rib,
        {
          prefix,
          Enum.find_value(path_attributes, fn
            %Attribute{value: %Attribute.NextHop{value: value}} -> value
            _attribute -> nil
          end)
        }
      )
    end

    Logger.info("#{data.config[:server]}: exiting Phase 2: Route Selection")

    data
  end

  defp prefix_feasible?(path_attributes) do
    nexthop_reachable?(path_attributes) && not as_path_loops?(path_attributes)
  end

  defp nexthop_reachable?(path_attributes) do
    Enum.find_value(path_attributes, false, fn
      %Attribute{value: %Attribute.NextHop{value: _value}} ->
        true

      _attribute ->
        false
    end)
  end

  defp as_path_loops?(path_attributes) do
    Enum.find_value(path_attributes, false, fn
      %Attribute{value: %Attribute.ASPath{value: {_type, _length, value}}} ->
        Enum.find_value(value, false, fn _asn -> false end)

      _attribute ->
        false
    end)
  end

  defp select_prefix(entry, current), do: highest_preference(entry, current)

  defp highest_preference(
         {_key, preference, _path_attributes} = entry,
         {_current_key, current_preference, _current_path_attributes}
       )
       when preference > current_preference,
       do: entry

  defp highest_preference(entry, current), do: tie_break(entry, current)

  defp tie_break(entry, current), do: lower_as_path_length(entry, current)

  defp lower_as_path_length(
         {_key, _preference, path_attributes} = entry,
         {_current_key, _current_preference, current_path_attributes} = current
       ) do
    as_path_length = as_path_length(path_attributes)
    current_as_path_length = as_path_length(current_path_attributes)

    cond do
      as_path_length < current_as_path_length -> entry
      as_path_length > current_as_path_length -> current
      as_path_length == current_as_path_length -> lowest_origin(entry, current)
    end
  end

  defp as_path_length(path_attributes) do
    Enum.find_value(path_attributes, fn
      %Attribute{value: %Attribute.ASPath{value: {_type, length, _value}}} -> length
      _attribute -> nil
    end)
  end

  defp lowest_origin(
         {_key, _preference, path_attributes} = entry,
         {_current_key, _current_preference, current_path_attributes} = current
       ) do
    origin = origin(path_attributes)
    current_origin = origin(current_path_attributes)

    cond do
      origin < current_origin -> entry
      origin > current_origin -> current
      origin == current_origin -> highest_med(entry, current)
    end
  end

  defp origin(path_attributes) do
    Enum.find_value(path_attributes, fn
      %Attribute{value: %Attribute.Origin{value: value}} -> value
      _attribute -> nil
    end)
  end

  defp highest_med(
         {_key, _preference, path_attributes} = entry,
         {_current_key, _current_preference, current_path_attributes} = current
       ) do
    med = med(path_attributes)
    current_med = med(current_path_attributes)

    cond do
      med > current_med -> entry
      med < current_med -> current
      med == current_med -> ebgp_over_ibgp(entry, current)
    end
  end

  defp med(path_attributes) do
    Enum.find_value(path_attributes, 0, fn
      %Attribute{value: %Attribute.MultiExitDisc{value: value}} -> value
      _attribute -> nil
    end)
  end

  defp ebgp_over_ibgp(entry, current), do: lowest_igp_cost(entry, current)

  defp lowest_igp_cost(entry, current), do: lowest_bgp_id(entry, current)

  defp lowest_bgp_id(
         {{bgp_id, _prefix}, _preference, _path_attributes} = entry,
         {{current_bgp_id, _current_prefix}, _current_preference, _current_path_attributes} =
           current
       ) do
    cond do
      bgp_id < current_bgp_id -> entry
      bgp_id > current_bgp_id -> current
      bgp_id == current_bgp_id -> lowest_peer_ip_address(entry, current)
    end
  end

  defp lowest_peer_ip_address(
         {{bgp_id, _prefix}, _preference, _path_attributes} = entry,
         {{current_bgp_id, _current_prefix}, _current_preference, _current_path_attributes} =
           current
       ) do
    cond do
      bgp_id < current_bgp_id -> entry
      bgp_id > current_bgp_id -> current
    end
  end

  defp route_dissemination(%__MODULE__{} = data) do
    Logger.info("#{data.config[:server]}: entering Phase 3: Route Dissemination")
    data = %__MODULE__{data | adj_ribs_out: data.loc_rib}
    Logger.info("#{data.config[:server]}: exiting Phase 3: Route Dissemination")
    data
  end
end
