defmodule BGP.Server.Session do
  @moduledoc """
  BGP Session
  """

  use Connection

  alias BGP.{Message, Prefix}
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
      Connection.start_link(__MODULE__, options, name: via(options[:server], options[:asn]))
    end
  end

  defp via(server, asn),
    do: {:via, Registry, {BGP.Server.Session.Registry, {server, asn}}}

  @spec incoming_connection(t(), BGP.bgp_id()) :: :ok | {:error, :collision}
  def incoming_connection(session, bgp_id),
    do: Connection.call(session, {:incoming_connection, bgp_id})

  @spec manual_start(t()) :: :ok | {:error, :already_started}
  def manual_start(session), do: Connection.call(session, {:start, :manual})

  @spec manual_stop(t()) :: :ok | {:error, :already_stopped}
  def manual_stop(session), do: Connection.call(session, {:stop, :manual})

  @spec session_for(BGP.Server.t(), BGP.asn()) :: {:ok, GenServer.server()} | {:error, :not_found}
  def session_for(server, asn) do
    case Registry.lookup(BGP.Server.Session.Registry, {server, asn}) do
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
  def handle_call({:incoming_connection, _bgp_id}, _from, state) do
    {:reply, :ok, state}
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

  def handle_info(
        {:tcp, _port, data},
        %{fsm: fsm, buffer: buffer, socket: socket} = state
      ) do
    :inet.setopts(socket, active: :once)

    try do
      (buffer <> data)
      |> Message.stream!()
      |> Enum.reduce({:noreply, state}, fn {rest, msg}, _return ->
        with {:ok, fsm, effects} <- FSM.event(fsm, {:msg, msg, :recv}),
             {:ok, state} <- process_effects(%{state | buffer: rest, fsm: fsm}, effects) do
          {:noreply, state}
        end
      end)
    catch
      %Encoder.Error{} = error ->
        data = Message.encode(Encoder.Error.to_notification(error), [])

        with {:ok, state} <- process_effects(state, {:msg, data, :send}),
             do: {:disconnect, error, state}
    end
  end

  def handle_info({:timer, _timer, :expires} = event, state) do
    with {:ok, state} <- trigger_event(state, event),
         do: {:noreply, state}
  end

  defp trigger_event(%{fsm: fsm} = state, event) do
    with {:ok, fsm, effects} <- FSM.event(fsm, event),
         do: process_effects(%{state | fsm: fsm}, effects)
  end

  defp process_effects(state, effects) do
    Logger.debug("Processing FSM effects: #{inspect(effects)}")

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
