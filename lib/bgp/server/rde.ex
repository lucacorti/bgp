defmodule BGP.Server.RDE do
  @moduledoc false

  @behaviour :gen_statem

  alias BGP.{Message.UPDATE, Server}

  require Logger

  @enforce_keys [:config]
  defstruct [:config]

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(args),
    do: :gen_statem.start_link({:local, Server.rde_for(args[:server])}, __MODULE__, args, [])

  @doc false
  def child_spec({args, opts}),
    do: %{id: make_ref(), start: {__MODULE__, :start_link, [{args, opts}]}}

  def child_spec(opts),
    do: %{id: make_ref(), start: {__MODULE__, :start_link, [opts]}}

  @spec process_update(Server.t(), UPDATE.t()) :: :ok
  def process_update(server, update),
    do: GenServer.call(Server.rde_for(server), {:process_update, update})

  @impl :gen_statem
  def callback_mode, do: [:handle_event_function, :state_enter]

  @impl :gen_statem
  def init(args), do: {:ok, :ready, %__MODULE__{config: args}}

  @impl :gen_statem
  def handle_event(:enter, old_state, new_state, %__MODULE__{}) do
    Logger.info("#{old_state} -> #{new_state}")
    :keep_state_and_data
  end

  @impl :gen_statem
  def handle_event({:call, from}, {:process_update, %UPDATE{}}, _state, _data) do
    {:keep_state_and_data, {:reply, from, :ok}}
  end
end
