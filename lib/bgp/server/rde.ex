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
    Idle --> DegreeOfPreference : recv UPDATE
    DegreeOfPreference --> Idle : Process UPDATE
  ```
  """
  @behaviour :gen_statem

  alias BGP.Message.UPDATE
  alias BGP.Message.UPDATE.Attribute
  alias BGP.Server
  alias BGP.Server.RDE.RIB
  alias BGP.Server.Session

  require Logger

  @enforce_keys [:config, :adj_ribs_in]
  defstruct [:config, :adj_ribs_in]

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(args),
    do: :gen_statem.start_link({:local, Server.rde_for(args[:server])}, __MODULE__, args, [])

  @doc false
  def child_spec({args, opts}),
    do: %{id: make_ref(), start: {__MODULE__, :start_link, [{args, opts}]}}

  def child_spec(opts),
    do: %{id: make_ref(), start: {__MODULE__, :start_link, [opts]}}

  @spec process_update(Server.t(), Session.data(), UPDATE.t()) :: :ok
  def process_update(server, session, update),
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
        adj_ribs_in: RIB.new(:adj_ribs_in)
      }
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
        {:process_update, _session, _update},
        :idle,
        data
      ) do
    {:next_state, :degree_of_preference, data, [{:reply, from, :ok}, :postpone]}
  end

  @impl :gen_statem
  def handle_event(
        {:call, _from},
        {:process_update, %Session{} = session, %UPDATE{} = update},
        :degree_of_preference,
        %__MODULE__{} = data
      ) do
    for route <- update.nlri do
      preference = degree_of_preference(session, update, route)
      RIB.upsert(data.adj_ribs_in, {{session.bgp_id, route}, preference, update.path_attributes})
    end

    for route <- update.withdrawn_routes do
      RIB.delete(data.adj_ribs_in, {session.bgp_id, route})
    end

    Logger.info("#{data.config[:server]}: #{RIB.dump(data.adj_ribs_in) |> Enum.count()} prefixes")

    {:next_state, :idle, data}
  end

  @impl :gen_statem
  def handle_event({:call, from}, {:process_update, _session, _update}, _state, _data),
    do: {:keep_state_and_data, [{:reply, from, :ok}, :postpone]}

  defp degree_of_preference(%Session{ibgp: true} = session, path_attributes, route) do
    Enum.find_value(path_attributes, pib_preference(session, path_attributes, route), fn
      %Attribute{value: %Attribute.LocalPref{value: value}} -> value
      _attribute -> nil
    end)
  end

  defp degree_of_preference(%Session{ibgp: false} = session, path_attributes, route),
    do: pib_preference(session, path_attributes, route)

  defp pib_preference(_session, _path_attributes, _route), do: 0
end
