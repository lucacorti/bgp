defmodule BGP.Server.Session do
  @moduledoc """
  BGP Session
  """

  use Connection

  alias BGP.{Message, Prefix, Server}
  alias BGP.Message.Encoder
  alias BGP.Server.FSM

  require Logger

  @type t :: GenServer.server()

  @options_schema NimbleOptions.new!(
                    automatic: [
                      doc: "Automatically start the peering session.",
                      type: :boolean,
                      default: true
                    ],
                    asn: [
                      doc: "Peer Autonomous System Number.",
                      type: :pos_integer,
                      default: 23_456
                    ],
                    bgp_id: [
                      doc: "Peer BGP ID, IP address.",
                      type: :string,
                      required: true
                    ],
                    host: [
                      doc: "Peer IP address as `:string`.",
                      type: {:custom, Prefix, :parse, []},
                      required: true
                    ],
                    mode: [
                      doc: "Actively connects to the peer or just waits for a connection",
                      type: {:in, [:active, :passive]},
                      default: :active
                    ],
                    port: [
                      doc: "Peer TCP port.",
                      type: :integer,
                      default: 179
                    ],
                    server: [
                      doc: "BGP Server the peer refers to",
                      type: :atom,
                      required: true
                    ]
                  )

  @typedoc """
  Supported options:

  #{NimbleOptions.docs(@options_schema)}
  """
  @type options() :: keyword()

  def child_spec(opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}

  def start_link(args) do
    with {:ok, options} <- NimbleOptions.validate(args, @options_schema) do
      Connection.start_link(__MODULE__, options, name: via(options[:server], options[:host]))
    end
  end

  defp via(server, host),
    do: {:via, Registry, {BGP.Server.Session.Registry, {server, host}}}

  @spec incoming_connection(t(), BGP.bgp_id()) :: :ok | {:error, :collision}
  def incoming_connection(session, peer_bgp_id),
    do: Connection.call(session, {:incoming_connection, peer_bgp_id})

  @spec manual_start(t()) :: :ok | {:error, :already_started}
  def manual_start(session), do: Connection.call(session, {:start, :manual})

  @spec manual_stop(t()) :: :ok | {:error, :already_stopped}
  def manual_stop(session), do: Connection.call(session, {:stop, :manual})

  @spec session_for(BGP.Server.t(), Prefix.t()) ::
          {:ok, GenServer.server()} | {:error, :not_found}
  def session_for(server, host) do
    case Registry.lookup(BGP.Server.Session.Registry, {server, host}) do
      [] -> {:error, :not_found}
      [{pid, _value}] -> {:ok, pid}
    end
  end

  @impl Connection
  def init(options) do
    state = %{buffer: <<>>, options: options, fsm: FSM.new(options), socket: nil}

    if options[:automatic] do
      trigger_event(state, {:start, :automatic, options[:mode]})
    else
      {:ok, state}
    end
  end

  @impl Connection
  def connect(info, %{options: options} = state) do
    case :gen_tcp.connect(options[:host], options[:port], mode: :binary, active: :once) do
      {:ok, socket} ->
        Logger.info("Connected on #{info}")

        trigger_event(%{state | socket: socket}, {:tcp_connection, :request_acked})

      {:error, _} ->
        Logger.error("Connection error on #{info}")

        {:ok, %{state | socket: nil, buffer: <<>>}}
    end
  end

  @impl Connection
  def disconnect(info, %{socket: socket} = state) do
    :ok = :gen_tcp.close(socket)
    Logger.debug("Connection closed, reason: #{inspect(info)}")

    {:noconnect, %{state | buffer: <<>>, socket: nil}}
  end

  @impl Connection
  def handle_call({:incoming_connection, peer_bgp_id}, _from, %{options: options} = state) do
    server_bgp_id =
      options
      |> Keyword.get(:server)
      |> Server.get_config(:bgp_id)

    if server_bgp_id > peer_bgp_id do
      {:reply, {:error, :collision}, state}
    else
      with {:ok, state} <- trigger_event(state, {:open, :collision_dump}),
           do: {:reply, :ok, state}
    end
  end

  def handle_call({:start, :manual}, _from, %{options: options} = state) do
    with {:ok, state} <- trigger_event(state, {:start, :manual, options[:mode]}),
         do: {:reply, :ok, state}
  end

  def handle_call({:stop, :manual}, _from, state) do
    with {:ok, state} <- trigger_event(state, {:stop, :manual}),
         do: {:reply, :ok, state}
  end

  @impl Connection
  def handle_info({:tcp_closed, _port}, state) do
    with {:ok, state} <- trigger_event(state, {:tcp_connection, :fails}),
         do: {:noreply, state}
  end

  def handle_info({:tcp, socket, data}, %{buffer: buffer, socket: socket} = state) do
    :inet.setopts(socket, active: :once)

    (buffer <> data)
    |> Message.stream!()
    |> Enum.reduce({:noreply, state}, fn {rest, msg}, {:noreply, state} ->
      with {:ok, state} <- trigger_event(state, {:msg, msg, :recv}) do
        {:noreply, %{state | buffer: rest}}
      end
    end)
  catch
    %Encoder.Error{} = error ->
      data = Message.encode(Encoder.Error.to_notification(error), [])
      process_effect(state, {:msg, data, :send})
      {:disconnect, error, state}
  end

  def handle_info({:timer, _timer, :expires} = event, state) do
    with {:ok, state} <- trigger_event(state, event),
         do: {:noreply, state}
  end

  defp trigger_event(%{fsm: fsm} = state, event) do
    Logger.debug("CONNECTION: Triggering FSM event: #{inspect(event)}")

    with {:ok, fsm, effects} <- FSM.event(fsm, event),
         do: process_effects(%{state | fsm: fsm}, effects)
  end

  defp process_effects(state, effects) do
    Logger.debug("CONNECTION: Processing FSM effects: #{inspect(effects)}")

    Enum.reduce(effects, {:ok, state}, fn effect, return ->
      case process_effect(state, effect) do
        :ok ->
          return

        {action, reason} ->
          {action, reason, state}
      end
    end)
  end

  defp process_effect(_state, {:msg, _msg, :recv}), do: :ok

  defp process_effect(%{socket: socket}, {:msg, data, :send}) do
    case :gen_tcp.send(socket, data) do
      :ok -> :ok
      {:error, reason} -> {:disconnect, reason}
    end
  end

  defp process_effect(_state, {:tcp_connection, :connect}), do: {:connect, :fsm}
  defp process_effect(_state, {:tcp_connection, :disconnect}), do: {:disconnect, :fsm}
end
