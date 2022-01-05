defmodule BGP.Session do
  @moduledoc """
  BGP Session
  """

  use Connection

  alias BGP.{FSM, Message, Prefix}

  require Logger

  @type t :: GenServer.server()

  @options_schema NimbleOptions.new!(
                    asn: [
                      doc: "Peer Autonomous System Number.",
                      type: :pos_integer,
                      default: 23_456
                    ],
                    automatic: [
                      doc: "Automatically start the peering session.",
                      type: :boolean,
                      default: true
                    ],
                    bgp_id: [
                      doc: "Peer BGP Id, IP address as `:string`.",
                      type: {:custom, Prefix, :parse, []},
                      required: true
                    ],
                    connect_retry: [
                      type: :keyword_list,
                      keys: [
                        secs: [doc: "Connect Retry timer seconds.", type: :non_neg_integer]
                      ],
                      default: [secs: 120]
                    ],
                    delay_open: [
                      type: :keyword_list,
                      keys: [
                        enabled: [doc: "Enable Delay OPEN.", type: :boolean],
                        secs: [doc: "Delay OPEN timer seconds.", type: :non_neg_integer]
                      ],
                      default: [enabled: true, secs: 5]
                    ],
                    hold_time: [
                      type: :keyword_list,
                      keys: [secs: [doc: "Hold Time timer seconds.", type: :non_neg_integer]],
                      default: [secs: 90]
                    ],
                    keep_alive: [
                      type: :keyword_list,
                      keys: [secs: [doc: "Keep Alive timer seconds.", type: :non_neg_integer]],
                      default: [secs: 30]
                    ],
                    host: [
                      doc: "Peer IP address as `:string`.",
                      type: {:custom, Prefix, :parse, []},
                      required: true
                    ],
                    notification_without_open: [
                      doc: "Allows NOTIFICATIONS to be received without OPEN first",
                      type: :boolean,
                      default: true
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
                    ]
                  )

  @typedoc """
  Supported options:

  #{NimbleOptions.docs(@options_schema)}
  """
  @type options() :: keyword()

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  def start_link(args) do
    with {:ok, options} <- NimbleOptions.validate(args, @options_schema),
         do: Connection.start_link(__MODULE__, options, name: __MODULE__)
  end

  @spec manual_start(t()) :: :ok | {:error, :already_started}
  def manual_start(connection), do: Connection.call(connection, {{:start, :manual}})

  @spec manual_stop(t()) :: :ok | {:error, :already_stopped}
  def manual_stop(connection), do: Connection.call(connection, {{:stop, :manual}})

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
        Logger.metadata(socket: socket)
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
  def handle_call({{:start, :manual}}, _from, %{options: options} = state) do
    with {:ok, state} <- trigger_event(state, {:start, :manual, options[:mode]}),
         do: {:reply, :ok, state}
  end

  def handle_call({{:stop, :manual}}, _from, state) do
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

    (buffer <> data)
    |> Message.stream()
    |> Enum.reduce({:noreply, state}, fn {rest, msg}, _return ->
      with {:ok, fsm, effects} <- FSM.event(fsm, {:msg, msg, :recv}),
           {:ok, state} <- process_effects(%{state | buffer: rest, fsm: fsm}, effects) do
        {:noreply, state}
      end
    end)
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
