defmodule BGP.Server.Session do
  @moduledoc "BGP Finite State Machine"

  @behaviour :gen_statem

  alias BGP.{Message, Server}
  alias BGP.Message.{KEEPALIVE, NOTIFICATION, OPEN, UPDATE}
  alias BGP.Message.OPEN.Capabilities
  alias BGP.Message.UPDATE.Attribute
  alias BGP.Message.UPDATE.Attribute.{ASPath, NextHop, Origin}
  alias BGP.Server.Session.Timer

  require Logger

  @asn_2octets_max 2 ** 16 - 1
  @as_trans 23_456

  @type mode :: :active | :passive
  @type start :: :manual | :automatic
  @type state :: :idle | :active | :open_sent | :open_confirm | :established

  @type data :: %__MODULE__{
          asn: BGP.asn(),
          bgp_id: BGP.bgp_id(),
          buffer: binary(),
          counters: %{atom() => non_neg_integer()},
          extended_message: boolean(),
          extended_optional_parameters: boolean(),
          four_octets: boolean(),
          host: IP.Address.t(),
          ibgp: boolean(),
          mode: mode(),
          networks: [IP.Prefix.t()],
          notification_without_open: boolean(),
          port: :inet.port_number(),
          server: Server.t(),
          socket: :gen_tcp.socket(),
          start: start(),
          timers: %{atom() => Timer.t()}
        }

  @type t :: :gen_statem.server_ref()

  @enforce_keys [
    :asn,
    :bgp_id,
    :host,
    :mode,
    :notification_without_open,
    :port,
    :server,
    :start
  ]
  defstruct asn: nil,
            bgp_id: nil,
            buffer: <<>>,
            counters: %{connect_retry: 0},
            extended_message: false,
            extended_optional_parameters: false,
            four_octets: false,
            host: nil,
            ibgp: false,
            mode: nil,
            networks: [],
            notification_without_open: nil,
            port: nil,
            server: nil,
            socket: nil,
            start: nil,
            timers: %{}

  @doc false
  def child_spec(opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}

  @spec incoming_connection(t(), BGP.bgp_id()) :: :ok | {:error, :collision}
  def incoming_connection(session, peer_bgp_id),
    do: :gen_statem.call(session, {:incoming_connection, peer_bgp_id})

  @spec manual_start(t()) :: :ok | {:error, :already_started}
  def manual_start(session), do: :gen_statem.call(session, {:start, :manual})

  @spec manual_stop(t()) :: :ok | {:error, :already_stopped}
  def manual_stop(session), do: :gen_statem.call(session, {:stop, :manual})

  @spec session_for(BGP.Server.t(), IP.Address.t()) ::
          {:ok, GenServer.server()} | {:error, :not_found}
  def session_for(server, host) do
    case Registry.lookup(Module.concat(server, Session.Registry), host) do
      [] -> {:error, :not_found}
      [{pid, _value}] -> {:ok, pid}
    end
  end

  @spec start_link(term()) :: :gen_statem.start_ret()
  def start_link(args) do
    :gen_statem.start_link(
      {
        :via,
        Registry,
        {Module.concat(args[:server], Session.Registry), args[:host]}
      },
      __MODULE__,
      args,
      []
      # debug: [:trace]
    )
  end

  @impl :gen_statem
  def callback_mode, do: [:handle_event_function, :state_enter]

  @impl :gen_statem
  def init(peer) do
    server = Server.get_config(peer[:server])

    data =
      struct(__MODULE__,
        asn: server[:asn],
        bgp_id: server[:bgp_id],
        host: peer[:host],
        mode: peer[:mode],
        networks: server[:networks],
        notification_without_open: peer[:notification_without_open],
        port: peer[:port],
        server: peer[:server],
        start: peer[:start],
        timers:
          Enum.into(
            [
              :as_origination,
              :connect_retry,
              :delay_open,
              :hold_time,
              :keep_alive,
              :route_advertisement
            ],
            %{},
            &{&1, Timer.new(get_in(peer, [&1, :seconds]), get_in(peer, [&1, :enabled?]) != false)}
          )
      )

    {:ok, :idle, data, [{:next_event, :internal, {:start, data.start, data.mode}}]}
  end

  @impl :gen_statem
  def handle_event(:enter, old_state, new_state, %__MODULE__{} = data) do
    Logger.debug("peer #{data.host}: #{old_state} -> #{new_state}")
    :keep_state_and_data
  end

  def handle_event(:internal, {:tcp_connection, :connect}, _state, %__MODULE__{} = data) do
    host =
      IP.Address.to_string(data.host)
      |> String.to_charlist()

    case :gen_tcp.connect(host, data.port, mode: :binary, active: :once) do
      {:ok, socket} ->
        {
          :keep_state,
          %{data | socket: socket},
          [{:next_event, :internal, {:tcp_connection, :request_acked}}]
        }

      {:error, error} ->
        Logger.error("Connection to peer #{data.host} failed, reason: #{error}")
        {:keep_state, %{data | socket: nil, buffer: <<>>}}
    end
  end

  def handle_event(:internal, {:tcp_connection, :disconnect}, _state, %__MODULE__{} = data) do
    :ok = :gen_tcp.close(data.socket)
    Logger.error("Connection to peer #{data.host} closed")

    {
      :keep_state,
      %{data | buffer: <<>>, socket: nil},
      [{:next_event, :internal, {:tcp_connection, :fails}}]
    }
  end

  def handle_event(:internal, {:send, %msg_type{} = msg}, _state, %__MODULE__{} = data) do
    {msg_data, data} = Message.encode(msg, data)

    case :gen_tcp.send(data.socket, msg_data) do
      :ok ->
        Logger.debug("peer #{data.host}: sending #{msg_type}")
        :keep_state_and_data

      {:error, _reason} ->
        Logger.error("Error sending #{msg_type} to peer #{data.host} failed")
        {:keep_state, [{:next_event, :internal, {:tcp_connection, :fails}}]}
    end
  end

  def handle_event(:info, {:tcp_closed, _port}, _state, %__MODULE__{} = data) do
    Logger.error("Connection closed by peer #{data.host}")
    {:keep_state_and_data, [{:next_event, :internal, {:tcp_connection, :fails}}]}
  end

  def handle_event(:info, {:tcp, socket, tcp_data}, _state, %__MODULE__{} = data) do
    {actions, data} =
      (data.buffer <> tcp_data)
      |> Message.stream!()
      |> Enum.map_reduce(data, fn {rest, msg_data}, %__MODULE__{} = data ->
        {%msg_type{} = msg, data} = Message.decode(msg_data, data)
        Logger.debug("peer #{data.host}: received #{msg_type}")
        {{:next_event, :internal, {:recv, msg}}, %{data | buffer: rest}}
      end)

    {:keep_state, data, actions}
  catch
    :error, %NOTIFICATION{} = error ->
      Logger.error("peer #{data.host}: error decoding message: #{inspect(error)}")

      {
        :keep_state_and_data,
        [
          {:next_event, :internal, {:send, error}},
          {:next_event, :internal, {:tcp_connection, :disconnect}}
        ]
      }
  after
    :inet.setopts(socket, active: :once)
  end

  def handle_event(:internal, {:increment_counter, counter}, _state, %__MODULE__{} = data) do
    {
      :keep_state,
      %{data | counters: update_in(data.counters, [counter], &(&1 + 1))}
    }
  end

  def handle_event(:internal, {:zero_counter, counter}, _state, %__MODULE__{} = data) do
    {
      :keep_state,
      %{data | counters: update_in(data.counters, [counter], fn _ -> 0 end)}
    }
  end

  def handle_event(:internal, {:set_timer, timer, value}, _state, %__MODULE__{} = data) do
    {
      :keep_state,
      %{data | timers: update_in(data.timers, [timer], &Timer.set(&1, value))}
    }
  end

  def handle_event(:internal, {:restart_timer, timer, value}, _state, %__MODULE__{} = data) do
    new_timer =
      get_in(data.timers, [timer])
      |> Timer.restart(value)

    {
      :keep_state,
      %{data | timers: update_in(data.timers, [timer], fn _ -> new_timer end)},
      [
        {:next_event, :internal, {:set_timer, timer, value}},
        {{:timeout, timer}, new_timer.value * 1_000, new_timer.value}
      ]
    }
  end

  def handle_event(:internal, {:stop_timer, timer}, _state, %__MODULE__{} = data) do
    {
      :keep_state,
      %{data | timers: update_in(data.timers, [timer], &Timer.stop/1)},
      [{{:timeout, timer}, :cancel}]
    }
  end

  def handle_event({:call, from}, {:incoming_connection, _peer_bgp_id}, :established, _data),
    do: {:keep_state_and_data, [{:reply, from, {:error, :collision}}]}

  def handle_event(
        {:call, from},
        {:incoming_connection, peer_bgp_id},
        state,
        %__MODULE__{} = data
      )
      when state in [:open_confirm, :open_sent] and data.bgp_id > peer_bgp_id,
      do: {:keep_state_and_data, [{:reply, from, {:error, :collision}}]}

  def handle_event({:call, from}, {:incoming_connection, _peer_bgp_id}, state, %__MODULE__{})
      when state in [:open_confirm, :open_sent] do
    {:keep_state_and_data, [{:reply, from, :ok}, {:next_event, :internal, :open_collision_dump}]}
  end

  def handle_event({:call, from}, {:incoming_connection, _peer_bgp_id}, _state, _data),
    do: {:keep_state_and_data, [{:reply, from, :ok}]}

  def handle_event({:call, from}, {:stop, _type}, :idle, _data),
    do: {:keep_state_and_data, [{:reply, from, :ok}]}

  def handle_event(:internal, {:start, :automatic, :active}, :idle, data) do
    {
      :next_state,
      :connect,
      data,
      [
        {:next_event, :internal, {:zero_counter, :connect_retry}},
        {:next_event, :internal, {:restart_timer, :connect_retry, nil}},
        {:next_event, :internal, {:tcp_connection, :connect}}
      ]
    }
  end

  def handle_event({:call, from}, {:start, :manual, :active}, :idle, data) do
    {
      :next_state,
      :connect,
      data,
      [
        {:next_event, :internal, {:zero_counter, :connect_retry}},
        {:next_event, :internal, {:restart_timer, :connect_retry, nil}},
        {:next_event, :internal, {:tcp_connection, :connect}},
        {:reply, from, :ok}
      ]
    }
  end

  def handle_event(:internal, {:start, :automatic, :passive}, :idle, data) do
    {
      :next_state,
      :active,
      data,
      [
        {:next_event, :internal, {:zero_counter, :connect_retry}},
        {:next_event, :internal, {:restart_timer, :connect_retry, nil}}
      ]
    }
  end

  def handle_event({:call, from}, {:start, :manual, :passive}, :idle, data) do
    {
      :next_state,
      :active,
      data,
      [
        {:next_event, :internal, {:zero_counter, :connect_retry}},
        {:next_event, :internal, {:restart_timer, :connect_retry, nil}},
        {:reply, from, :ok}
      ]
    }
  end

  def handle_event(_event_type, _event, :idle, _data), do: :keep_state_and_data

  def handle_event(_event_type, {:start, _type, _mode}, :connect, _data), do: :keep_state_and_data

  def handle_event({:call, from}, {:stop, :manual}, :connect, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:zero_counter, :connect_retry}},
        {:next_event, :internal, {:stop_timer, :connect_retry}},
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:tcp_connection, :disconnect}},
        {:reply, from, :ok}
      ]
    }
  end

  def handle_event({:timeout, :connect_retry}, _event, :connect, _data) do
    {
      :keep_state_and_data,
      [
        {:next_event, :internal, {:restart_timer, :connect_retry, nil}},
        {:next_event, :internal, {:stop_timer, :delay_open}},
        {:next_event, :internal, {:set_timer, :delay_open, 0}},
        {:next_event, :internal, {:tcp_connection, :connect}}
      ]
    }
  end

  def handle_event({:timeout, :delay_open}, _event, :connect, data) do
    {
      :next_state,
      :open_sent,
      data,
      [
        {:next_event, :internal, {:set_timer, :hold_time}},
        {:next_event, :internal, {:send, compose_open(data)}}
      ]
    }
  end

  def handle_event(:internal, {:tcp_connection, event}, :connect, data)
      when event in [:confirmed, :request_acked] do
    if timer_enabled?(data, :delay_open) do
      {
        :keep_state_and_data,
        [
          {:next_event, :internal, {:stop_timer, :connect_retry}},
          {:next_event, :internal, {:set_timer, :connect_retry, 0}},
          {:next_event, :internal, {:restart_timer, :delay_open, nil}}
        ]
      }
    else
      {
        :keep_state_and_data,
        [
          {:next_event, :internal, {:stop_timer, :connect_retry}},
          {:next_event, :internal, {:set_timer, :connect_retry, 0}},
          {:next_event, :internal, {:restart_timer, :hold_time, nil}},
          {:next_event, :internal, {:send, compose_open(data)}}
        ]
      }
    end
  end

  def handle_event(:internal, {:tcp_connection, :fails}, :connect, data) do
    if timer_running?(data, :delay_open) do
      {
        :next_state,
        :active,
        data,
        [
          {:next_event, :internal, {:restart_timer, :connect_retry, nil}},
          {:next_event, :internal, {:stop_timer, :delay_open}}
        ]
      }
    else
      {
        :next_state,
        :idle,
        data,
        [
          {:next_event, :internal, {:stop_timer, :connect_retry}},
          {:next_event, :internal, {:set_timer, :connect_retry, 0}}
        ]
      }
    end
  end

  def handle_event(:internal, {:recv, msg}, :connect, data) do
    delay_open_timer_running = timer_running?(data, :delay_open)

    case msg do
      %OPEN{hold_time: hold_time} when delay_open_timer_running and hold_time > 0 ->
        {
          :next_state,
          :open_confirm,
          data,
          [
            {:next_event, :internal, {:restart_timer, :keep_alive, div(hold_time, 3)}},
            {:next_event, :internal, {:restart_timer, :hold_time, hold_time}},
            {:next_event, :internal, {:stop_timer, :connect_retry}},
            {:next_event, :internal, {:set_timer, :connect_retry, 0}},
            {:next_event, :internal, {:stop_timer, :delay_open}},
            {:next_event, :internal, {:set_timer, :delay_open, 0}},
            {:next_event, :internal, {:send, compose_open(data)}},
            {:next_event, :internal, {:send, %KEEPALIVE{}}}
          ]
        }

      %OPEN{} when delay_open_timer_running ->
        {
          :next_state,
          :open_confirm,
          data,
          [
            {:next_event, :internal, {:restart_timer, :keep_alive, nil}},
            {:next_event, :internal, {:set_timer, :hold_time, nil}},
            {:next_event, :internal, {:stop_timer, :connect_retry}},
            {:next_event, :internal, {:set_timer, :connect_retry, 0}},
            {:next_event, :internal, {:stop_timer, :delay_open}},
            {:next_event, :internal, {:set_timer, :delay_open, 0}},
            {:next_event, :internal, {:send, compose_open(data)}},
            {:next_event, :internal, {:send, %KEEPALIVE{}}}
          ]
        }

      %NOTIFICATION{code: :unsupported_version_number} when delay_open_timer_running ->
        {
          :next_state,
          :idle,
          data,
          [
            {:next_event, :internal, {:stop_timer, :connect_retry}},
            {:next_event, :internal, {:set_timer, :connect_retry, 0}},
            {:next_event, :internal, {:stop_timer, :delay_open}},
            {:next_event, :internal, {:set_timer, :delay_open, 0}},
            {:next_event, :internal, {:tcp_connection, :disconnect}}
          ]
        }

      %NOTIFICATION{code: :unsupported_version_number} ->
        {
          :next_state,
          :idle,
          data,
          [
            {:next_event, :internal, {:stop_timer, :connect_retry}},
            {:next_event, :internal, {:set_timer, :connect_retry, 0}},
            {:next_event, :internal, {:increment_counter, :connect_retry}},
            {:next_event, :internal, {:tcp_connection, :disconnect}}
          ]
        }
    end
  end

  def handle_event(_type, _event, :connect, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:stop_timer, :connect_retry}},
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:stop_timer, :delay_open}},
        {:next_event, :internal, {:set_timer, :delay_open, 0}},
        {:next_event, :internal, {:increment_counter, :connect_retry}}
      ]
    }
  end

  def handle_event(:internal, {:start, _type, _mode}, :active, _data), do: :keep_state_and_data

  def handle_event(
        {:call, from},
        {:stop, :manual},
        :active,
        %__MODULE__{notification_without_open: true} = data
      ) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:stop_timer, :delay_open}},
        {:next_event, :internal, {:zero_counter, :connect_retry}},
        {:next_event, :internal, {:stop_timer, :connect_retry}},
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:send, %NOTIFICATION{code: :cease}}},
        {:next_event, :internal, {:tcp_connection, :disconnect}},
        {:reply, from, :ok}
      ]
    }
  end

  def handle_event({:call, from}, {:stop, :manual}, :active, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:stop_timer, :delay_open}},
        {:next_event, :internal, {:zero_counter, :connect_retry}},
        {:next_event, :internal, {:stop_timer, :connect_retry}},
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:tcp_connection, :disconnect}},
        {:reply, from, :ok}
      ]
    }
  end

  def handle_event({:timeout, :connect_retry}, _event, :active, data) do
    {
      :next_state,
      :connect,
      data,
      [{:next_event, :internal, {:restart_timer, :connect_retry, nil}}]
    }
  end

  def handle_event({:timeout, :delay_open}, _event, :active, data) do
    {
      :next_state,
      :open_sent,
      data,
      [
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:stop_timer, :delay_open}},
        {:next_event, :internal, {:set_timer, :delay_open, 0}},
        {:next_event, :internal, {:set_timer, :hold_time}},
        {:next_event, :internal, {:send, compose_open(data)}}
      ]
    }
  end

  def handle_event(:internal, {:tcp_connection, event}, :active, data)
      when event in [:confirmed, :request_acked] do
    if timer_enabled?(data, :delay_open) do
      {
        :keep_state_and_data,
        [
          {:next_event, :internal, {:stop_timer, :connect_retry}},
          {:next_event, :internal, {:set_timer, :connect_retry, 0}},
          {:next_event, :internal, {:restart_timer, :delay_open, nil}}
        ]
      }
    else
      {
        :next_state,
        :open_sent,
        data,
        [
          {:next_event, :internal, {:set_timer, :connect_retry, 0}},
          {:next_event, :internal, {:set_timer, :hold_time, nil}},
          {:next_event, :internal, {:send, compose_open(data)}}
        ]
      }
    end
  end

  def handle_event(:internal, {:tcp_connection, :fails}, :active, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:restart_timer, :connect_retry, 0}},
        {:next_event, :internal, {:stop_timer, :delay_open}},
        {:next_event, :internal, {:set_timer, :delay_open, 0}},
        {:next_event, :internal, {:increment_counter, :connect_retry}}
      ]
    }
  end

  def handle_event(:internal, {:recv, msg}, :active, data) do
    delay_open_timer_running = timer_running?(data, :delay_open)

    case msg do
      %OPEN{hold_time: hold_time} when delay_open_timer_running and hold_time > 0 ->
        {
          :next_state,
          :open_confirm,
          data,
          [
            {:next_event, :internal, {:restart_timer, :keep_alive, div(hold_time, 3)}},
            {:next_event, :internal, {:restart_timer, :hold_time, hold_time}},
            {:next_event, :internal, {:stop_timer, :connect_retry}},
            {:next_event, :internal, {:set_timer, :connect_retry, 0}},
            {:next_event, :internal, {:stop_timer, :delay_open}},
            {:next_event, :internal, {:set_timer, :delay_open, 0}},
            {:next_event, :internal, {:send, compose_open(data)}},
            {:next_event, :internal, {:send, %KEEPALIVE{}}}
          ]
        }

      %OPEN{hold_time: hold_time} when delay_open_timer_running and hold_time > 0 ->
        {
          :next_state,
          :open_confirm,
          data,
          [
            {:next_event, :internal, {:set_timer, :keep_alive, 0}},
            {:next_event, :internal, {:set_timer, :hold_time, 0}},
            {:next_event, :internal, {:stop_timer, :connect_retry}},
            {:next_event, :internal, {:set_timer, :connect_retry, 0}},
            {:next_event, :internal, {:stop_timer, :delay_open}},
            {:next_event, :internal, {:set_timer, :delay_open, 0}},
            {:next_event, :internal, {:send, compose_open(data)}},
            {:next_event, :internal, {:send, %KEEPALIVE{}}}
          ]
        }

      %NOTIFICATION{code: :unsupported_version_number} when delay_open_timer_running ->
        {
          :next_state,
          :idle,
          data,
          [
            {:next_event, :internal, {:stop_timer, :connect_retry}},
            {:next_event, :internal, {:set_timer, :connect_retry, 0}},
            {:next_event, :internal, {:stop_timer, :delay_open}},
            {:next_event, :internal, {:set_timer, :delay_open, 0}},
            {:next_event, :internal, {:tcp_connection, :disconnect}}
          ]
        }

      %NOTIFICATION{code: :unsupported_version_number} ->
        {
          :next_state,
          :idle,
          data,
          [
            {:next_event, :internal, {:set_timer, :connect_retry, 0}},
            {:next_event, :internal, {:increment_counter, :connect_retry}},
            {:next_event, :internal, {:tcp_connection, :disconnect}}
          ]
        }
    end
  end

  def handle_event(_type, _event, :active, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:increment_counter, :connect_retry}},
        {:next_event, :internal, {:tcp_connection, :disconnect}}
      ]
    }
  end

  def handle_event({:call, from}, {:start, _type, _mode}, :open_sent, _data),
    do: {:keep_state_and_data, [{:reply, from, :ok}]}

  def handle_event({:call, from}, {:stop, :manual}, :open_sent, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:zero_counter, :connect_retry}},
        {:next_event, :internal, {:send, %NOTIFICATION{code: :cease}}},
        {:reply, from, :ok}
      ]
    }
  end

  def handle_event({:call, from}, {:stop, :automatic}, :open_sent, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:increment_counter, :connect_retry}},
        {:next_event, :internal, {:send, %NOTIFICATION{code: :cease}}},
        {:next_event, :internal, {:tcp_connection, :disconnect}},
        {:reply, from, :ok}
      ]
    }
  end

  def handle_event({:timeout, :hold_time}, _event, :open_sent, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:increment_counter, :connect_retry}},
        {:next_event, :internal, {:send, %NOTIFICATION{code: :hold_timer_expired}}},
        {:next_event, :internal, {:tcp_connection, :disconnect}}
      ]
    }
  end

  def handle_event(:internal, {:tcp_connection, :fails}, :open_sent, %__MODULE__{} = data) do
    {
      :next_state,
      :active,
      data,
      [
        {:next_event, :internal, {:restart_timer, :connect_retry, nil}},
        {:next_event, :internal, {:tcp_connection, :disconnect}}
      ]
    }
  end

  def handle_event(:internal, :open_collision_dump, :open_sent, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:increment_counter, :connect_retry}},
        {:next_event, :internal, {:send, %NOTIFICATION{code: :cease}}},
        {:next_event, :internal, {:tcp_connection, :disconnect}},
        {:stop, :normal}
      ]
    }
  end

  def handle_event(:internal, {:recv, msg}, :open_sent, data) do
    case msg do
      %OPEN{hold_time: hold_time} when hold_time > 0 ->
        {
          :next_state,
          :open_confirm,
          data,
          [
            {:next_event, :internal, {:set_timer, :delay_open, 0}},
            {:next_event, :internal, {:set_timer, :connect_retry, 0}},
            {:next_event, :internal, {:restart_timer, :keep_alive, div(hold_time, 3)}},
            {:next_event, :internal, {:restart_timer, :hold_time, hold_time}},
            {:next_event, :internal, {:send, %KEEPALIVE{}}}
          ]
        }

      %OPEN{} ->
        {
          :next_state,
          :open_confirm,
          data,
          [
            {:next_event, :internal, {:set_timer, :delay_open, 0}},
            {:next_event, :internal, {:set_timer, :connect_retry, 0}},
            {:next_event, :internal, {:stop_timer, :keep_alive}},
            {:next_event, :internal, {:send, %KEEPALIVE{}}}
          ]
        }

      %NOTIFICATION{code: :unsupported_version_number} ->
        {
          :next_state,
          :idle,
          data,
          [
            {:next_event, :internal, {:set_timer, :connect_retry, 0}},
            {:next_event, :internal, {:tcp_connection, :disconnect}}
          ]
        }
    end
  end

  def handle_event(_type, _event, :open_sent, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:increment_counter, :connect_retry}},
        {:next_event, :internal, {:send, %NOTIFICATION{code: :fsm}}},
        {:next_event, :internal, {:tcp_connection, :disconnect}}
      ]
    }
  end

  def handle_event({:call, from}, {:start, _type, _mode}, :open_confirm, _data),
    do: {:keep_state_and_data, [{:reply, from, :ok}]}

  def handle_event({:call, from}, {:stop, :manual}, :open_confirm, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:zero_counter, :connect_retry}},
        {:next_event, :internal, {:send, %NOTIFICATION{code: :cease}}},
        {:next_event, :internal, {:tcp_connection, :disconnect}},
        {:reply, from, :ok}
      ]
    }
  end

  def handle_event({:call, from}, {:stop, :automatic}, :open_confirm, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:increment_counter, :connect_retry}},
        {:next_event, :internal, {:send, %NOTIFICATION{code: :cease}}},
        {:next_event, :internal, {:tcp_connection, :disconnect}},
        {:reply, from, :ok}
      ]
    }
  end

  def handle_event({:timeout, :hold_time}, _event, :open_confirm, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:increment_counter, :connect_retry}},
        {:next_event, :internal, {:send, %NOTIFICATION{code: :hold_timer_expired}}},
        {:next_event, :internal, {:tcp_connection, :disconnect}}
      ]
    }
  end

  def handle_event({:timeout, :keep_alive}, _event, :open_confirm, _data) do
    {
      :keep_state_and_data,
      [
        {:next_event, :internal, {:restart_timer, :keep_alive, nil}},
        {:next_event, :internal, {:send, %KEEPALIVE{}}}
      ]
    }
  end

  def handle_event(:internal, {:tcp_connection, :fails}, :open_confirm, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:increment_counter, :connect_retry}},
        {:next_event, :internal, {:tcp_connection, :disconnect}}
      ]
    }
  end

  def handle_event(
        :internal,
        {:recv, %NOTIFICATION{code: :unsupported_version_number}},
        :open_confirm,
        data
      ) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:tcp_connection, :disconnect}}
      ]
    }
  end

  def handle_event(:internal, :open_collision_dump, :open_confirm, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:increment_counter, :connect_retry}},
        {:next_event, :internal, {:send, %NOTIFICATION{code: :cease}}},
        {:next_event, :internal, {:tcp_connection, :disconnect}},
        {:stop, :normal}
      ]
    }
  end

  def handle_event(:internal, {:recv, msg}, :open_confirm, %__MODULE__{} = data) do
    case msg do
      %NOTIFICATION{} ->
        {
          :next_state,
          :idle,
          data,
          [
            {:next_event, :internal, {:set_timer, :connect_retry, 0}},
            {:next_event, :internal, {:increment_counter, :connect_retry}},
            {:next_event, :internal, {:tcp_connection, :disconnect}}
          ]
        }

      %OPEN{} ->
        {
          :next_state,
          :idle,
          data,
          [
            {:next_event, :internal, {:set_timer, :connect_retry, 0}},
            {:next_event, :internal, {:increment_counter, :connect_retry}},
            {:next_event, :internal, {:send, %NOTIFICATION{code: :cease}}}
          ]
        }

      %KEEPALIVE{} ->
        {
          :next_state,
          :established,
          data,
          [
            {:next_event, :internal, {:restart_timer, :as_origination, nil}},
            {:next_event, :internal, {:restart_timer, :hold_time, nil}},
            {:next_event, :internal, {:restart_timer, :route_advertisement, nil}},
            {:next_event, :internal, {:send, compose_as_update(data)}}
          ]
        }
    end
  end

  def handle_event(_type, _event, :open_confirm, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:increment_counter, :connect_retry}},
        {:next_event, :internal, {:send, %NOTIFICATION{code: :fsm}}},
        {:next_event, :internal, {:tcp_connection, :disconnect}}
      ]
    }
  end

  def handle_event({:call, from}, {:start, _type, _mode}, :established, _data),
    do: {:keep_state_and_data, [{:reply, from, :ok}]}

  def handle_event({:call, from}, {:stop, :manual}, :established, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:set_timer, :as_origination, 0}},
        {:next_event, :internal, {:set_timer, :route_advertisement, 0}},
        {:next_event, :internal, {:set_counter, :connect_retry, 0}},
        {:next_event, :internal, {:send, %NOTIFICATION{code: :cease}}},
        {:next_event, :internal, {:tcp_connection, :disconnect}},
        {:reply, from, :ok}
      ]
    }
  end

  def handle_event({:call, from}, {:stop, :automatic}, :established, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:set_timer, :as_origination, 0}},
        {:next_event, :internal, {:set_timer, :route_advertisement, 0}},
        {:next_event, :internal, {:increment_counter, :connect_retry}},
        {:next_event, :internal, {:send, %NOTIFICATION{code: :cease}}},
        {:next_event, :internal, {:tcp_connection, :disconnect}},
        {:reply, from, :ok}
      ]
    }
  end

  def handle_event({:timeout, :as_origination}, _event, :established, data) do
    {
      :keep_state_and_data,
      [
        {:next_event, :internal, {:restart_timer, :as_origination, nil}},
        {:next_event, :internal, {:send, compose_as_update(data)}}
      ]
    }
  end

  def handle_event({:timeout, :hold_time}, _event, :established, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:set_timer, :as_origination, 0}},
        {:next_event, :internal, {:set_timer, :route_advertisement, 0}},
        {:next_event, :internal, {:increment_counter, :connect_retry}},
        {:next_event, :internal, {:send, %NOTIFICATION{code: :hold_time_expired}}},
        {:next_event, :internal, {:tcp_connection, :disconnect}}
      ]
    }
  end

  def handle_event({:timeout, :keep_alive}, _event, :established, %__MODULE__{} = data) do
    if timer_seconds(data, :hold_time) > 0 do
      {
        :keep_state_and_data,
        [
          {:next_event, :internal, {:restart_timer, :keep_alive, nil}},
          {:next_event, :internal, {:send, %KEEPALIVE{}}}
        ]
      }
    else
      {:keep_state_and_data, [{:next_event, :internal, {:send, %KEEPALIVE{}}}]}
    end
  end

  def handle_event({:timeout, :route_advertisement}, _event, :established, _data) do
    {
      :keep_state_and_data,
      [{:next_event, :internal, {:restart_timer, :route_advertisement, nil}}]
    }
  end

  def handle_event(:internal, {:tcp_connection, :fails}, :established, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:set_timer, :as_origination, 0}},
        {:next_event, :internal, {:set_timer, :route_advertisement, 0}},
        {:next_event, :internal, {:increment_counter, :connect_retry}},
        {:next_event, :internal, {:tcp_connection, :disconnect}}
      ]
    }
  end

  def handle_event(:internal, :open_collision_dump, :established, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:set_timer, :as_origination, 0}},
        {:next_event, :internal, {:set_timer, :route_advertisement, 0}},
        {:next_event, :internal, {:increment_counter, :connect_retry}},
        {:next_event, :internal, {:send, %NOTIFICATION{code: :cease}}},
        {:next_event, :internal, {:tcp_connection, :disconnect}}
      ]
    }
  end

  def handle_event(:internal, {:recv, msg}, :established, %__MODULE__{} = data) do
    hold_time = timer_seconds(data, :hold_time)

    case msg do
      %OPEN{} ->
        {
          :next_state,
          :idle,
          data,
          [
            {:next_event, :internal, {:set_timer, :connect_retry, 0}},
            {:next_event, :internal, {:set_timer, :as_origination, 0}},
            {:next_event, :internal, {:set_timer, :route_advertisement, 0}},
            {:next_event, :internal, {:increment_counter, :connect_retry}},
            {:next_event, :internal, {:send, %NOTIFICATION{code: :cease}}},
            {:next_event, :internal, {:tcp_connection, :disconnect}}
          ]
        }

      %NOTIFICATION{} ->
        {
          :next_state,
          :idle,
          data,
          [
            {:next_event, :internal, {:set_timer, :connect_retry, 0}},
            {:next_event, :internal, {:set_timer, :as_origination, 0}},
            {:next_event, :internal, {:set_timer, :route_advertisement, 0}},
            {:next_event, :internal, {:increment_counter, :connect_retry}},
            {:next_event, :internal, {:tcp_connection, :disconnect}}
          ]
        }

      %KEEPALIVE{} when hold_time > 0 ->
        {:keep_state_and_data, [{:next_event, :internal, {:restart_timer, :hold_time, nil}}]}

      %KEEPALIVE{} ->
        :keep_state_and_data

      %UPDATE{} when hold_time > 0 ->
        {:keep_state_and_data, [{:next_event, :internal, {:restart_timer, :hold_time, nil}}]}

      %UPDATE{} ->
        :keep_state_and_data
    end
  end

  def handle_event(_type, _event, :establised, data) do
    {
      :next_state,
      :idle,
      data,
      [
        {:next_event, :internal, {:set_timer, :connect_retry, 0}},
        {:next_event, :internal, {:set_timer, :as_origination, 0}},
        {:next_event, :internal, {:set_timer, :route_advertisement, 0}},
        {:next_event, :internal, {:increment_counter, :connect_retry}},
        {:next_event, :internal, {:send, %NOTIFICATION{code: :cease}}},
        {:next_event, :internal, {:tcp_connection, :disconnect}}
      ]
    }
  end

  defp compose_open(%__MODULE__{} = data) do
    %OPEN{
      asn: compose_open_asn(data),
      bgp_id: data.bgp_id,
      hold_time: timer_seconds(data, :hold_time),
      capabilities: %Capabilities{
        four_octets_asn: true,
        multi_protocol: {:ipv4, :nlri_unicast},
        extended_message: true
      }
    }
  end

  defp compose_open_asn(%__MODULE__{asn: asn}) when asn < @asn_2octets_max, do: asn
  defp compose_open_asn(_data), do: @as_trans

  defp compose_as_update(%__MODULE__{} = data) do
    %UPDATE{
      path_attributes: [
        %Attribute{value: %Origin{origin: :igp}},
        %Attribute{value: %ASPath{value: [{:as_sequence, 1, [data.asn]}]}},
        %Attribute{value: %NextHop{value: data.bgp_id}}
      ],
      nlri: data.networks
    }
  end

  defp timer_enabled?(%__MODULE__{} = data, timer),
    do: get_in(data.timers, [timer]).enabled?

  defp timer_running?(%__MODULE__{} = data, timer),
    do: get_in(data.timers, [timer]).running?

  defp timer_seconds(%__MODULE__{} = data, timer),
    do: get_in(data.timers, [timer]).seconds
end
