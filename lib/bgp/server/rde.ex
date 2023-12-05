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

  @behaviour :gen_statem

  alias BGP.{Message.UPDATE, Server}
  alias BGP.Server.Session
  alias BGP.Server.Session.Group
  alias BGP.Message.UPDATE.Attribute
  alias BGP.Message.UPDATE.Attribute.{ASPath, LocalPref, MultiExitDisc, Origin}

  require Logger

  @enforce_keys [:adj_rib_in, :loc_rib, :queue, :server]

  defstruct adj_rib_in: nil, loc_rib: nil, queue: nil, server: nil

  @doc false
  def child_spec(server),
    do: %{id: Server.rde_for(server), start: {__MODULE__, :start_link, [server]}}

  @spec process_update(Session.data(), UPDATE.t()) :: :ok
  def process_update(%Session{} = data, update),
    do: :gen_statem.call(Server.rde_for(data.server), {:process_update, data, update})

  @spec start_link(term()) :: :gen_statem.start_ret()
  def start_link(server) do
    :gen_statem.start_link(
      {:local, Server.rde_for(server)},
      __MODULE__,
      [server],
      #      debug: [:trace]
      []
    )
  end

  def get_loc_rib(server) do
    server
    |> :ets.whereis()
    |> :ets.tab2list()
  end

  @impl :gen_statem
  #  def callback_mode, do: [:handle_event_function, :state_enter]
  def callback_mode, do: :handle_event_function

  @impl :gen_statem
  def init([server]) do
    Group.monitor(server)

    data = %__MODULE__{
      adj_rib_in: :ets.new(:adj_rib_in, [:set, :private]),
      loc_rib: :ets.new(server, [:named_table, :set, :protected]),
      queue: :queue.new(),
      server: server
    }

    {:ok, :idle, data, [{:state_timeout, 1_000, nil}]}
  end

  @impl :gen_statem
  # def handle_event(:enter, old_state, new_state, data) do
  #   Logger.debug("RDE: #{old_state} -> #{new_state}")

  #   all = :ets.tab2list(data.adj_rib_in)
  #   IO.inspect(all, label: :aaaaa)

  #   :keep_state_and_data
  # end

  def handle_event(:state_timeout, _, :idle, data) do
    {
      :next_state,
      :processing,
      data,
      [{:next_event, :internal, :process_update_internal}]
    }
  end

  def handle_event(:internal, :calculate, :processing, data) do
    # Phase 2: Route Selection
    out_res =
      data.adj_rib_in
      |> :ets.tab2list()
      #    |> Enum.filter(& filter_next_hop/1)
      |> Enum.filter(&filter_as_path/1)
      |> Enum.group_by(fn {{_host, _pid, prefix}, _path_attributes, _loc_pref, _session} ->
        prefix
      end)
      |> Enum.map(fn {prefix, adj_rib_in_items} ->
        res =
          adj_rib_in_items
          |> Enum.reduce(
            [],
            fn
              {_, _, _, _} = item, [] ->
                [item]

              {_, _, loc_pref, _} = item, [{_, _, loc_pref_acc, _} | _] = acc ->
                cond do
                  loc_pref > loc_pref_acc -> [item]
                  loc_pref == loc_pref_acc -> [item | acc]
                  true -> acc
                end
            end
          )

        {prefix, res}
      end)
      |> Enum.map(fn {_prefix, adj_rib_in_items} ->
        adj_rib_in_items
        |> Enum.reduce(
          [],
          fn
            {_, _, _, _} = item, [] ->
              [item]

            {_, path_attributes, _, _} = item, [{_, path_attributes_acc, _, _} | _] = acc ->
              as_path = filter_as_path_by_length(path_attributes)
              acc_as_path = filter_as_path_by_length(path_attributes_acc)

              cond do
                as_path < acc_as_path -> [item]
                as_path == acc_as_path -> [item | acc]
                true -> acc
              end
          end
        )
        |> Enum.reduce(
          [],
          fn
            {_, _, _, _} = item, [] ->
              [item]

            {_, path_attributes, _, _} = item, [{_, path_attributes_acc, _, _} | _] = acc ->
              origin = filter_origin(path_attributes)
              acc_origin = filter_origin(path_attributes_acc)

              cond do
                origin < acc_origin -> [item]
                origin == acc_origin -> [item | acc]
                true -> acc
              end
          end
        )
        |> Enum.reduce(
          %{},
          fn
            {{_host, _pid, _prefix}, path_attributes, _loc_pref, %Session{asn: asn}} = item,
            acc ->
              case acc[asn] || [] do
                [] ->
                  Map.put(acc, asn, [item])

                [_] ->
                  acc

                [{_, path_attributes_acc, _, _} | _] = items ->
                  multi_exit_disc = filter_multi_exit_disc(path_attributes)
                  acc_multi_exit_disc = filter_multi_exit_disc(path_attributes_acc)

                  cond do
                    multi_exit_disc < acc_multi_exit_disc -> Map.put(acc, asn, [item])
                    multi_exit_disc == acc_multi_exit_disc -> Map.put(acc, asn, [item | items])
                    true -> acc
                  end
              end
          end
        )
        |> Enum.flat_map(fn {_asn, prefixes} -> prefixes end)
        |> Kernel.then(fn items ->
          case filter_ebgp(items) do
            [] -> items
            ebgps -> ebgps
          end
        end)
        |> Enum.reduce(
          [],
          fn
            {_, _, _, _} = item, [] ->
              [item]

            {_, _, _, %Session{bgp_id: bgp_id}} = item,
            [{_, _, _, %Session{bgp_id: acc_bgp_id}} | _] = acc ->
              cond do
                bgp_id > acc_bgp_id -> [item]
                bgp_id == acc_bgp_id -> [item | acc]
                true -> acc
              end
          end
        )
        |> Enum.reduce(
          [],
          fn
            {{_host, _pid, prefix}, path_attributes, _, _}, [] ->
              [{prefix, path_attributes}]

            {{_host, _pid, prefix}, path_attributes, _, %Session{host: host}},
            [{_, _, _, %Session{host: acc_host}} | _] = acc ->
              cond do
                host < acc_host -> [{prefix, path_attributes}]
                true -> acc
              end
          end
        )
        |> List.flatten()
      end)

    :ets.delete_all_objects(data.loc_rib)
    :ets.insert(data.loc_rib, out_res)

    {
      :next_state,
      :idle,
      data,
      {:state_timeout, 1_000, nil}
    }
  end

  def handle_event(:info, {_ref, :join, _group, _pids}, _state, _data) do
    :keep_state_and_data
  end

  def handle_event(:info, {_ref, :leave, host, pids}, _state, data) do
    pids
    |> Enum.each(fn pid ->
      :ets.match_delete(data.adj_rib_in, {{host, pid, :_}, :_})
    end)

    all = :ets.tab2list(data.adj_rib_in)
    IO.inspect(all, label: :aaaaa)

    :keep_state_and_data
  end

  def handle_event(
        {:call, {pid, _} = from},
        {:process_update, %Session{} = session, update},
        :idle,
        %__MODULE__{} = data
      ) do
    {
      :keep_state,
      %{data | queue: :queue.in({session, update, pid}, data.queue)},
      {:reply, from, :ok}
    }
  end

  def handle_event({:call, from}, {:process_update, _session, _update}, _state, _data) do
    {:postpone, {:reply, from, :ok}}
  end

  def handle_event(:internal, :process_update_internal, :processing, %__MODULE__{} = data) do
    Stream.resource(
      fn -> data.queue end,
      fn queue ->
        case :queue.out(queue) do
          {{:value, update}, queue} -> {[update], queue}
          {:empty, queue} -> {:halt, queue}
        end
      end,
      fn _queue -> nil end
    )
    |> Enum.each(fn {%Session{} = session, %UPDATE{} = update, pid} ->
      update.withdrawn_routes
      |> Enum.each(fn prefix ->
        :ets.delete(data.adj_rib_in, {session.host, pid, prefix})
      end)

      object =
        update.nlri
        |> Enum.map(fn prefix ->
          loc_pref = degree_of_preference(session.ibgp, update.path_attributes)
          {{session.host, pid, prefix}, update.path_attributes, loc_pref, session}
        end)

      :ets.insert(data.adj_rib_in, object)
    end)

    {
      :keep_state,
      %{data | queue: :queue.new()},
      [{:next_event, :internal, :calculate}]
    }
  end

  # Phase 1: Calculation of Degree of Preference (https://www.rfc-editor.org/rfc/rfc4271#section-9.1.1)
  defp degree_of_preference(false, _path_attributes), do: 1

  defp degree_of_preference(true, path_attributes) do
    Enum.find_value(path_attributes, 1, fn
      %Attribute{value: %LocalPref{} = local_pref} -> local_pref.value
      _ -> nil
    end)
  end

  defp filter_as_path({{_host, _pid, _prefix}, path_attributes, _loc_pref, %Session{} = session}) do
    Enum.find_value(path_attributes, true, fn
      %Attribute{value: %ASPath{} = as_path} ->
        Enum.find_value(as_path.value, true, fn
          {_, _, asn} -> asn != session.asn
          _ -> nil
        end)

      _ ->
        nil
    end)
  end

  defp filter_as_path_by_length({{_host, _pid, _prefix}, path_attributes, _loc_pref, _session}) do
    Enum.find_value(path_attributes, fn
      %Attribute{value: %ASPath{value: {type, _length, _path}}}
      when type in [:as_set, :as_confed_set] ->
        1

      %Attribute{value: %ASPath{value: {_type, length, _path}}} ->
        length

      _ ->
        nil
    end)
  end

  defp filter_origin({{_host, _pid, _prefix}, path_attributes, _loc_pref, _session}) do
    Enum.find_value(path_attributes, fn
      %Attribute{value: %Origin{origin: origin}} ->
        case origin do
          :igp -> 0
          :egp -> 1
          :incomplete -> 2
        end

      _ ->
        nil
    end)
  end

  defp filter_multi_exit_disc({{_host, _pid, _prefix}, path_attributes, _loc_pref, _session}) do
    Enum.find_value(path_attributes, fn
      %Attribute{value: %MultiExitDisc{value: value}} ->
        value

      _ ->
        nil
    end)
  end

  defp filter_ebgp(items) do
    Enum.filter(items, fn {{_host, _pid, _prefix}, _path_attributes, _loc_pref,
                           %Session{ibgp: ibgp}} ->
      not ibgp
    end)
  end
end
