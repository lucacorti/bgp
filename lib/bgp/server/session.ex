defmodule BGP.Server.Session do
  @moduledoc """
  BGP Session
  """

  use Connection

  alias BGP.{FSM, Message, Prefix, Server}
  alias BGP.Message.{NOTIFICATION, OPEN}
  alias BGP.Server.Listener

  require Logger

  @type t :: GenServer.server()

  def child_spec(opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}

  def start_link(args) do
    Connection.start_link(
      __MODULE__,
      args,
      name: {:via, Registry, {BGP.Server.Session.Registry, {args[:server], args[:host]}}}
    )
  end

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
    state = %{
      buffer: <<>>,
      options: options,
      fsm: FSM.new(Server.get_config(options[:server]), options),
      socket: nil
    }

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
        Logger.debug("Connected on #{info}")

        trigger_event(%{state | socket: socket}, {:tcp_connection, :request_acked})

      {:error, error} ->
        Logger.error("Connection error on #{info}, reason: #{error}")

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
  def handle_call(
        {:incoming_connection, _peer_bgp_id},
        _from,
        {_socket, %{fsm: %FSM{state: :established}}} = state
      ),
      do: {:reply, {:error, :collision}, state}

  def handle_call(
        {:incoming_connection, peer_bgp_id},
        _from,
        %{options: options, fsm: %FSM{state: fsm_state}} = state
      )
      when fsm_state in [:open_confirm, :open_sent] do
    server_bgp_id = Keyword.fetch!(options, :bgp_id)

    if server_bgp_id > peer_bgp_id do
      {:reply, {:error, :collision}, state}
    else
      Logger.warn("SESSION: closing connection to peer due to collision")

      case trigger_event(state, {:error, :open_collision_dump}) do
        {:ok, state} -> {:reply, :ok, state}
        {action, state} -> {action, state}
      end
    end
  end

  def handle_call({:incoming_connection, _peer_bgp_id}, _from, state), do: {:reply, :ok, state}

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

  def handle_info({:tcp, socket, data}, %{buffer: buffer, fsm: fsm, socket: socket} = state) do
    (buffer <> data)
    |> Message.stream!(fsm)
    |> Enum.reduce({:noreply, state}, fn {rest, msg}, {:noreply, state} ->
      with {:ok, state} <- trigger_event(state, {:recv, msg}) do
        {:noreply, %{state | buffer: rest}}
      end
    end)
  catch
    {:error, %NOTIFICATION{} = error} ->
      process_effect(state, {:send, error})
      {:disconnect, error, state}
  after
    :inet.setopts(socket, active: :once)
  end

  def handle_info({:timer, _timer, :expired} = event, state) do
    with {:ok, state} <- trigger_event(state, event),
         do: {:noreply, state}
  end

  defp trigger_event(%{fsm: fsm} = state, event) do
    Logger.debug("SESSION: Triggering FSM event: #{inspect(event)}")

    with {:ok, fsm, effects} <- FSM.event(fsm, event),
         do: process_effects(%{state | fsm: fsm}, effects)
  end

  defp process_effects(state, effects) do
    Enum.reduce(effects, {:ok, state}, fn effect, return ->
      Logger.debug("SESSION: Processing FSM effect: #{inspect(effect)}")

      case process_effect(state, effect) do
        :ok ->
          return

        {action, reason} ->
          {action, reason, state}
      end
    end)
  end

  defp process_effect(
         %{options: options, socket: socket} = state,
         {:recv, %OPEN{bgp_id: bgp_id}}
       ) do
    server = Keyword.get(options, :server)
    {:ok, {address, _port}} = :inet.peername(socket)

    with {:ok, connection} <- Listener.connection_for(server, address),
         :ok <- Listener.outbound_connection(connection, bgp_id) do
      Logger.debug("SESSION: No collision, keeping connection to peer #{address}")
      :ok
    else
      {:error, :collision} ->
        Logger.warn("SESSION: Connection to peer #{inspect(address)} collides, closing")

        case trigger_event(state, {:error, :open_collision_dump}) do
          {:ok, state} -> {:close, state}
          {action, state} -> {action, state}
        end

      {:error, :not_found} ->
        Logger.debug("SESSION: No inbound connection from peer #{inspect(address)}")
        :ok
    end
  end

  defp process_effect(_state, {:recv, _msg}), do: :ok

  defp process_effect(%{fsm: fsm, socket: socket}, {:send, msg}) do
    case :gen_tcp.send(socket, Message.encode(msg, fsm)) do
      :ok -> :ok
      {:error, reason} -> {:disconnect, reason}
    end
  end

  defp process_effect(_state, {:tcp_connection, :connect}), do: {:connect, :fsm}
  defp process_effect(_state, {:tcp_connection, :disconnect}), do: {:disconnect, :fsm}
end
