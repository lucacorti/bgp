defmodule BGP.Server.Session do
  @moduledoc false

  use Connection

  alias BGP.{FSM, Message, Server}
  alias BGP.Message.{NOTIFICATION, OPEN, UPDATE}
  alias BGP.Server.Listener

  require Logger

  @type t :: GenServer.server()

  def child_spec(opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}

  def start_link(args) do
    Connection.start_link(
      __MODULE__,
      args,
      name: {
        :via,
        Registry,
        {Module.concat(args[:server], Session.Registry), args[:host]}
      }
    )
  end

  @spec incoming_connection(t(), BGP.bgp_id()) :: :ok | {:error, :collision}
  def incoming_connection(session, peer_bgp_id),
    do: Connection.call(session, {:incoming_connection, peer_bgp_id})

  @spec manual_start(t()) :: :ok | {:error, :already_started}
  def manual_start(session), do: Connection.call(session, {:start, :manual})

  @spec manual_stop(t()) :: :ok | {:error, :already_stopped}
  def manual_stop(session), do: Connection.call(session, {:stop, :manual})

  @spec session_for(BGP.Server.t(), IP.Address.t()) ::
          {:ok, GenServer.server()} | {:error, :not_found}
  def session_for(server, host) do
    case Registry.lookup(Module.concat(server, Session.Registry), host) do
      [] -> {:error, :not_found}
      [{pid, _value}] -> {:ok, pid}
    end
  end

  @impl Connection
  def init(options) do
    state = %{
      buffer: <<>>,
      host: options[:host],
      mode: options[:mode],
      port: options[:port],
      fsm: FSM.new(Server.get_config(options[:server]), options),
      server: options[:server],
      socket: nil
    }

    if options[:automatic] do
      case trigger_event(state, {:start, :automatic, options[:mode]}) do
        {:ok, state} -> {:ok, state}
        {action, state} -> {action, :automatic, state}
      end
    else
      {:ok, state}
    end
  end

  @impl Connection
  def connect(info, %{host: host, port: port} = state) do
    host = IP.Address.to_string(host) |> String.to_charlist()

    case :gen_tcp.connect(host, port, mode: :binary, active: :once) do
      {:ok, socket} ->
        Logger.debug("Connected on #{info}")

        case trigger_event(%{state | socket: socket}, {:tcp_connection, :request_acked}) do
          {:ok, state} ->
            {:ok, state}

          {action, state} ->
            {action, :fsm, state}
        end

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
  def handle_call({:incoming_connection, peer_bgp_id}, _from, %{fsm: fsm} = state) do
    case FSM.check_collision(fsm, peer_bgp_id) do
      :ok ->
        {:reply, :ok, state}

      {:error, :collision} = error ->
        {:reply, error, state}

      {:error, :close} ->
        Logger.warning("SESSION: closing connection to peer due to collision")

        case trigger_event(state, {:error, :open_collision_dump}) do
          {:ok, state} -> {:reply, :ok, state}
          {action, state} -> {action, :fsm, :ok, state}
        end
    end
  end

  def handle_call({:start, :manual}, _from, %{mode: mode} = state) do
    case trigger_event(state, {:start, :manual, mode}) do
      {:ok, state} ->
        {:reply, :ok, state}

      {action, state} ->
        {action, :fsm, :ok, state}
    end
  end

  def handle_call({:stop, :manual}, _from, state) do
    case trigger_event(state, {:stop, :manual}) do
      {:ok, state} ->
        {:reply, :ok, state}

      {action, state} ->
        {action, :fsm, :ok, state}
    end
  end

  @impl Connection
  def handle_info({:tcp_closed, _port}, state) do
    case trigger_event(state, {:tcp_connection, :fails}) do
      {:ok, state} ->
        {:noreply, state}

      {action, state} ->
        {action, :fsm, state}
    end
  end

  def handle_info({:tcp, socket, data}, %{buffer: buffer, socket: socket} = state) do
    (buffer <> data)
    |> Message.stream!()
    |> Enum.reduce({:noreply, state}, fn {rest, data}, {:noreply, %{fsm: fsm} = state} ->
      with {msg, fsm} <- Message.decode(data, fsm),
           {:ok, state} <- trigger_event(%{state | fsm: fsm}, {:recv, msg}) do
        {:noreply, %{state | buffer: rest}}
      else
        {action, state} ->
          {action, :fsm, state}
      end
    end)
  catch
    :error, %NOTIFICATION{} = error ->
      case trigger_event(state, {:send, error}) do
        {:ok, state} ->
          {:noreply, state}

        {action, state} ->
          {action, :fsm, state}
      end
  after
    :inet.setopts(socket, active: :once)
  end

  def handle_info({:timer, timer, :expired} = event, state) do
    Logger.debug("SESSION: #{timer} timer expired")

    case trigger_event(state, event) do
      {:ok, state} ->
        {:noreply, state}

      {action, state} ->
        {action, :fsm, state}
    end
  end

  defp trigger_event(%{fsm: fsm} = state, event) do
    with {:ok, fsm, effects} <- FSM.event(fsm, event) do
      Enum.reduce(effects, {:ok, %{state | fsm: fsm}}, fn effect, {action, state} ->
        case process_effect(state, effect) do
          {:ok, state} ->
            {action, state}

          {action, state} ->
            {action, state}
        end
      end)
    end
  end

  defp process_effect(
         %{server: server, socket: socket} = state,
         {:recv, %OPEN{bgp_id: bgp_id}}
       ) do
    with {:ok, {address, _port}} <- :inet.peername(socket),
         {:ok, host} <- IP.Address.from_tuple(address),
         {:ok, connection} <- Listener.connection_for(server, host),
         :ok <- Listener.outbound_connection(connection, bgp_id) do
      Logger.debug("SESSION: No collision, keeping connection to peer #{address}")
      {:ok, state}
    else
      {:error, :collision} ->
        Logger.warning("SESSION: Connection to peer collides, closing")

        with {:ok, state} <- trigger_event(state, {:error, :open_collision_dump}),
             do: {:close, state}

      {:error, reason} ->
        Logger.debug("SESSION: No inbound connection from peer, continuing: #{inspect(reason)}")
        {:ok, state}
    end
  end

  defp process_effect(%{server: server} = state, {:recv, %UPDATE{} = message}) do
    with :ok <- Server.RDE.process_update(server, message), do: {:ok, state}
  end

  defp process_effect(%{fsm: fsm, socket: socket} = state, {:send, msg}) do
    {data, fsm} = Message.encode(msg, fsm)

    case :gen_tcp.send(socket, data) do
      :ok -> {:ok, %{state | fsm: fsm}}
      {:error, _reason} -> {:disconnect, state}
    end
  end

  defp process_effect(state, {:tcp_connection, :connect}), do: {:connect, state}
  defp process_effect(state, {:tcp_connection, :disconnect}), do: {:disconnect, state}
end
