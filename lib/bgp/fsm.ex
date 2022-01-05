defmodule BGP.FSM do
  @moduledoc false

  alias BGP.FSM.Timer
  alias BGP.{Message, Session}
  alias BGP.Message.{KEEPALIVE, NOTIFICATION, OPEN, UPDATE}
  alias BGP.Message.OPEN.Parameter.Capabilities

  require Logger

  @type connection_op :: :connect | :disconnect
  @type msg_op :: :recv | :send

  @type effect ::
          {:msg, Message.t(), msg_op()}
          | {:tcp_connection, connection_op()}

  @type start_type :: :manual | :automatic
  @type stop_type :: start_type()
  @type start_passivity :: :active | :passive
  @type connection_event :: :confirmed | :fails | :request_acked
  @type timer_event :: :expires

  @type event ::
          {:msg, Message.t(), :recv}
          | {:tcp_connection, connection_event()}
          | {:start, start_type(), start_passivity()}
          | {:stop, stop_type()}
          | {:timer, Timer.name(), timer_event()}

  @type counter :: pos_integer()
  @type state :: :idle | :active | :open_sent | :open_confirm | :established

  @type t :: %__MODULE__{
          asn: BGP.asn(),
          bgp_id: BGP.bgp_id(),
          counters: keyword(counter()),
          delay_open: boolean(),
          delay_open_time: non_neg_integer(),
          four_octets: boolean(),
          hold_time: BGP.hold_time(),
          internal: boolean(),
          notification_without_open: boolean(),
          options: Session.options(),
          state: state(),
          timers: keyword(Timer.t())
        }

  @enforce_keys [
    :asn,
    :bgp_id,
    :delay_open,
    :delay_open_time,
    :hold_time,
    :notification_without_open,
    :options
  ]
  defstruct asn: nil,
            bgp_id: nil,
            counters: [connect_retry: 0],
            delay_open: nil,
            delay_open_time: nil,
            four_octets: false,
            hold_time: nil,
            internal: false,
            notification_without_open: nil,
            options: [],
            state: :idle,
            timers: [
              connect_retry: Timer.new(0),
              delay_open: Timer.new(0),
              hold_time: Timer.new(0),
              keep_alive: Timer.new(0)
            ]

  @spec new(Session.options()) :: t()
  def new(options),
    do:
      struct(__MODULE__,
        asn: options[:asn],
        bgp_id: options[:bgp_id],
        delay_open: options[:delay_open][:enabled],
        delay_open_time: options[:delay_open][:secs],
        hold_time: options[:hold_time][:secs],
        notification_without_open: options[:notification_without_open],
        options: options
      )

  @spec event(t(), event()) :: {:ok, t(), [effect()]}
  def event(%{state: old_state} = fsm, event) do
    with {:ok, fsm, effects} <- process_event(fsm, event) do
      Logger.debug("FSM state: #{old_state} -> #{fsm.state}")
      {:ok, fsm, effects}
    end
  end

  defp process_event(%__MODULE__{state: :idle} = fsm, {:stop, _type}),
    do: {:ok, fsm, []}

  defp process_event(%__MODULE__{state: :idle} = fsm, {:start, _type, :active}),
    do: {
      :ok,
      %__MODULE__{fsm | state: :connect}
      |> zero_counter(:connect_retry)
      |> stop_timer(:connect_retry)
      |> init_timer(:connect_retry)
      |> start_timer(:connect_retry),
      [{:tcp_connection, :connect}]
    }

  defp process_event(%__MODULE__{state: :idle} = fsm, {:start, _type, :passive}),
    do: {
      :ok,
      %__MODULE__{fsm | state: :active}
      |> zero_counter(:connect_retry)
      |> stop_timer(:connect_retry)
      |> init_timer(:connect_retry)
      |> start_timer(:connect_retry),
      []
    }

  defp process_event(%__MODULE__{state: :idle} = fsm, _event), do: {:ok, fsm, []}

  defp process_event(%__MODULE__{state: :connect} = fsm, {:start, _type, _passivity}),
    do: {:ok, fsm, []}

  defp process_event(%__MODULE__{state: :connect} = fsm, {:stop, :manual}),
    do: {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> zero_counter(:connect_retry)
      |> stop_timer(:connect_retry)
      |> init_timer(:connect_retry, 0),
      [{:tcp_connection, :disconnect}]
    }

  defp process_event(%__MODULE__{state: :connect} = fsm, {:timer, :connect_retry, :expires}),
    do: {
      :ok,
      fsm
      |> stop_timer(:connect_retry)
      |> init_timer(:connect_retry)
      |> start_timer(:connect_retry)
      |> stop_timer(:delay_open)
      |> init_timer(:delay_open, 0),
      [{:tcp_connection, :connect}]
    }

  defp process_event(%__MODULE__{state: :connect} = fsm, {:timer, :delay_open, :expires}) do
    {
      :ok,
      %__MODULE__{fsm | state: :open_sent}
      |> init_timer(:hold_time),
      [{:msg, compose_open(fsm), :send}]
    }
  end

  defp process_event(
         %__MODULE__{delay_open: true, state: :connect} = fsm,
         {:tcp_connection, event}
       )
       when event in [:confirmed, :request_acked] do
    {
      :ok,
      fsm
      |> stop_timer(:connect_retry)
      |> init_timer(:connect_retry, 0)
      |> init_timer(:delay_open)
      |> start_timer(:delay_open),
      []
    }
  end

  defp process_event(
         %__MODULE__{delay_open: false, state: :connect} = fsm,
         {:tcp_connection, event}
       )
       when event in [:confirmed, :request_acked] do
    {
      :ok,
      %__MODULE__{fsm | state: :open_sent}
      |> stop_timer(:connect_retry)
      |> init_timer(:connect_retry, 0)
      |> init_timer(:hold_time),
      [{:msg, compose_open(fsm), :send}]
    }
  end

  defp process_event(%__MODULE__{state: :connect} = fsm, {:tcp_connection, :fails}) do
    if timer_running?(fsm, :delay_open) do
      {
        :ok,
        %__MODULE__{fsm | state: :active}
        |> stop_timer(:connect_retry)
        |> init_timer(:connect_retry)
        |> start_timer(:connect_retry)
        |> stop_timer(:delay_open)
        |> init_timer(:delay_open, 0),
        []
      }
    else
      {
        :ok,
        %__MODULE__{fsm | state: :idle}
        |> stop_timer(:connect_retry)
        |> init_timer(:connect_retry, 0),
        []
      }
    end
  end

  defp process_event(%__MODULE__{state: :connect} = fsm, {:msg, msg, :recv}) do
    delay_open_running = timer_running?(fsm, :delay_open)

    case decode_msg(fsm, msg) do
      {:ok, %OPEN{hold_time: hold_time} = open} when delay_open_running and hold_time > 0 ->
        {
          :ok,
          %__MODULE__{fsm | state: :open_confirm}
          |> process_open(open)
          |> stop_timer(:connect_retry)
          |> init_timer(:connect_retry, 0)
          |> stop_timer(:delay_open)
          |> init_timer(:delay_open, 0)
          |> stop_timer(:keep_alive)
          |> init_timer(:keep_alive)
          |> start_timer(:keep_alive)
          |> stop_timer(:hold_time)
          |> init_timer(:hold_time, hold_time)
          |> start_timer(:hold_time),
          [{:msg, compose_open(fsm), :send}, {:msg, compose_msg(fsm, %KEEPALIVE{}), :send}]
        }

      {:ok, %OPEN{} = open} when delay_open_running ->
        {
          :ok,
          %__MODULE__{fsm | state: :open_confirm}
          |> process_open(open)
          |> stop_timer(:connect_retry)
          |> init_timer(:connect_retry, 0)
          |> stop_timer(:delay_open)
          |> init_timer(:delay_open, 0)
          |> stop_timer(:keep_alive)
          |> init_timer(:keep_alive)
          |> start_timer(:keep_alive)
          |> init_timer(:hold_time),
          [{:msg, compose_open(fsm), :send}, {:msg, compose_msg(fsm, %KEEPALIVE{}), :send}]
        }

      {:ok, %OPEN{} = open} ->
        {:ok, process_open(fsm, open), []}

      {:ok, %NOTIFICATION{code: :unsupported_version_number}} when delay_open_running ->
        {
          :ok,
          %__MODULE__{fsm | state: :idle}
          |> stop_timer(:connect_retry)
          |> init_timer(:connect_retry, 0)
          |> stop_timer(:delay_open)
          |> init_timer(:delay_open, 0),
          [{:tcp_connection, :disconnect}]
        }

      {:ok, %NOTIFICATION{code: :unsupported_version_number}} ->
        {
          :ok,
          %__MODULE__{fsm | state: :idle}
          |> stop_timer(:connect_retry)
          |> init_timer(:connect_retry, 0)
          |> increment_counter(:connect_retry),
          [{:tcp_connection, :disconnect}]
        }
    end
  end

  defp process_event(%__MODULE__{state: :connect} = fsm, _event) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> stop_timer(:connect_retry)
      |> init_timer(:connect_retry, 0)
      |> stop_timer(:delay_open)
      |> init_timer(:delay_open, 0)
      |> increment_counter(:connect_retry),
      []
    }
  end

  defp process_event(%__MODULE__{state: :active} = fsm, {:start, _type, _passivity}),
    do: {:ok, fsm, []}

  defp process_event(
         %__MODULE__{notification_without_open: true, state: :active} = fsm,
         {:stop, :manual}
       ) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> stop_timer(:delay_open)
      |> zero_counter(:connect_retry)
      |> stop_timer(:connect_retry)
      |> init_timer(:connect_retry, 0),
      [
        {:msg, compose_msg(fsm, %NOTIFICATION{code: :cease}), :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :active} = fsm, {:stop, :manual}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> stop_timer(:delay_open)
      |> zero_counter(:connect_retry)
      |> stop_timer(:connect_retry)
      |> init_timer(:connect_retry, 0),
      [{:tcp_connection, :disconnect}]
    }
  end

  defp process_event(%__MODULE__{state: :active} = fsm, {:timer, :connect_retry, :expires}) do
    {
      :ok,
      %__MODULE__{fsm | state: :connect}
      |> init_timer(:connect_retry)
      |> start_timer(:connect_retry),
      []
    }
  end

  defp process_event(%__MODULE__{state: :active} = fsm, {:timer, :delay_open, :expires}) do
    {
      :ok,
      %__MODULE__{fsm | state: :open_sent}
      |> init_timer(:connect_retry, 0)
      |> stop_timer(:delay_open)
      |> init_timer(:delay_open, 0)
      |> init_timer(:hold_time),
      [{:msg, compose_open(fsm), :send}]
    }
  end

  defp process_event(
         %__MODULE__{delay_open: true, state: :active} = fsm,
         {:tcp_connection, event}
       )
       when event in [:confirmed, :request_acked] do
    {
      :ok,
      fsm
      |> stop_timer(:connect_retry)
      |> init_timer(:connect_retry, 0)
      |> init_timer(:delay_open),
      []
    }
  end

  defp process_event(
         %__MODULE__{delay_open: false, state: :active} = fsm,
         {:tcp_connection, event}
       )
       when event in [:confirmed, :request_acked] do
    {
      :ok,
      %__MODULE__{fsm | state: :open_sent}
      |> init_timer(:connect_retry, 0)
      |> init_timer(:hold_time),
      [{:msg, compose_open(fsm), :send}]
    }
  end

  defp process_event(%__MODULE__{state: :active} = fsm, {:tcp_connection, :fails}),
    do: {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> stop_timer(:connect_retry)
      |> init_timer(:connect_retry, 0)
      |> start_timer(:connect_retry)
      |> stop_timer(:delay_open)
      |> init_timer(:delay_open, 0)
      |> increment_counter(:connect_retry),
      []
    }

  defp process_event(%__MODULE__{state: :active} = fsm, {:msg, msg, :recv}) do
    delay_open_running = timer_running?(fsm, :delay_open)
    hold_timer_nonzero = timer_seconds(fsm, :hold_time) != 0

    case decode_msg(fsm, msg) do
      {:ok, %OPEN{hold_time: hold_time} = open}
      when delay_open_running and hold_timer_nonzero ->
        {
          :ok,
          %__MODULE__{fsm | state: :open_confirm}
          |> process_open(open)
          |> stop_timer(:connect_retry)
          |> init_timer(:connect_retry, 0)
          |> stop_timer(:delay_open)
          |> init_timer(:delay_open, 0)
          |> stop_timer(:keep_alive)
          |> init_timer(:keep_alive)
          |> start_timer(:keep_alive)
          |> stop_timer(:hold_time)
          |> init_timer(:hold_time, hold_time)
          |> start_timer(:hold_time),
          [{:msg, compose_open(fsm), :send}, {:msg, compose_msg(fsm, %KEEPALIVE{}), :send}]
        }

      {:ok, %OPEN{} = open} when hold_timer_nonzero ->
        {
          :ok,
          %__MODULE__{fsm | state: :open_confirm}
          |> process_open(open)
          |> stop_timer(:connect_retry)
          |> init_timer(:connect_retry, 0)
          |> stop_timer(:delay_open)
          |> init_timer(:delay_open, 0)
          |> init_timer(:keep_alive, 0)
          |> init_timer(:hold_time, 0),
          [{:msg, compose_open(fsm), :send}, {:msg, compose_msg(fsm, %KEEPALIVE{}), :send}]
        }

      {:ok, %NOTIFICATION{code: :unsupported_version_number}} when delay_open_running ->
        {
          :ok,
          %__MODULE__{fsm | state: :idle}
          |> stop_timer(:connect_retry)
          |> init_timer(:connect_retry, 0)
          |> stop_timer(:delay_open)
          |> init_timer(:delay_open, 0),
          [{:tcp_connection, :disconnect}]
        }

      {:ok, %NOTIFICATION{code: :unsupported_version_number}} ->
        {
          :ok,
          %__MODULE__{fsm | state: :idle}
          |> init_timer(:connect_retry, 0)
          |> increment_counter(:connect_retry),
          [{:tcp_connection, :disconnect}]
        }
    end
  end

  defp process_event(%__MODULE__{state: :active} = fsm, _event) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [{:tcp_connection, :disconnect}]
    }
  end

  defp process_event(%__MODULE__{state: :open_sent} = fsm, {:start, _type, _passivity}),
    do: {:ok, fsm, []}

  defp process_event(%__MODULE__{state: :open_sent} = fsm, {:stop, :manual}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> zero_counter(:connect_retry),
      [
        {:msg, compose_msg(fsm, %NOTIFICATION{code: :cease}), :send}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :open_sent} = fsm, {:stop, :automatic}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:msg, compose_msg(fsm, %NOTIFICATION{code: :cease}), :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :open_sent} = fsm, {:timer, :hold_time, :expires}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:msg, compose_msg(fsm, %NOTIFICATION{code: :hold_timer_expired}), :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :open_sent} = fsm, {:tcp_connection, :fails}) do
    {
      :ok,
      %__MODULE__{fsm | state: :active}
      |> stop_timer(:connect_retry)
      |> start_timer(:connect_retry),
      [{:tcp_connection, :disconnect}]
    }
  end

  defp process_event(%__MODULE__{state: :open_sent} = fsm, {:msg, msg, :recv}) do
    case decode_msg(fsm, msg) do
      {:ok, %OPEN{hold_time: hold_time} = open} when hold_time > 0 ->
        {
          :ok,
          %__MODULE__{fsm | state: :open_confirm}
          |> process_open(open)
          |> init_timer(:delay_open, 0)
          |> init_timer(:connect_retry, 0)
          |> stop_timer(:keep_alive)
          |> stop_timer(:keep_alive)
          |> init_timer(:keep_alive)
          |> start_timer(:keep_alive)
          |> stop_timer(:hold_time)
          |> init_timer(:hold_time, hold_time)
          |> start_timer(:hold_time),
          [
            {:msg, compose_msg(fsm, %KEEPALIVE{}), :send}
          ]
        }

      {:ok, %OPEN{} = open} ->
        {
          :ok,
          %__MODULE__{fsm | state: :open_confirm}
          |> process_open(open)
          |> init_timer(:delay_open, 0)
          |> init_timer(:connect_retry, 0)
          |> stop_timer(:keep_alive),
          [
            {:msg, compose_msg(fsm, %KEEPALIVE{}), :send}
          ]
        }

      {:ok, %NOTIFICATION{code: :unsupported_version_number}} ->
        {
          :ok,
          %__MODULE__{fsm | state: :idle}
          |> init_timer(:connect_retry, 0),
          [{:tcp_connection, :disconnect}]
        }
    end
  end

  defp process_event(%__MODULE__{state: :open_sent} = fsm, _event) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:msg, compose_msg(fsm, %NOTIFICATION{code: :fsm}), :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :open_confirm} = fsm, {:start, _type, _passivity}),
    do: {:ok, fsm, []}

  defp process_event(%__MODULE__{state: :open_confirm} = fsm, {:stop, :manual}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> zero_counter(:connect_retry),
      [
        {:msg, compose_msg(fsm, %NOTIFICATION{code: :cease}), :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :open_confirm} = fsm, {:stop, :automatic}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:msg, compose_msg(fsm, %NOTIFICATION{code: :cease}), :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :open_confirm} = fsm, {:timer, :hold_time, :expires}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:msg, compose_msg(fsm, %NOTIFICATION{code: :hold_timer_expired}), :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :open_confirm} = fsm, {:timer, :keep_alive, :expires}) do
    {
      :ok,
      fsm
      |> stop_timer(:keep_alive)
      |> init_timer(:keep_alive)
      |> start_timer(:keep_alive),
      [
        {:msg, compose_msg(fsm, %KEEPALIVE{}), :send}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :open_confirm} = fsm, {:tcp_connection, :fails}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [{:tcp_connection, :disconnect}]
    }
  end

  defp process_event(
         %__MODULE__{state: :open_confirm} = fsm,
         {:msg, %NOTIFICATION{code: :unsupported_version_number}, :recv}
       ) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0),
      [{:tcp_connection, :disconnect}]
    }
  end

  defp process_event(%__MODULE__{state: :open_confirm} = fsm, {:msg, msg, :recv}) do
    case decode_msg(fsm, msg) do
      {:ok, %NOTIFICATION{}} ->
        {
          :ok,
          %__MODULE__{fsm | state: :idle}
          |> init_timer(:connect_retry, 0)
          |> increment_counter(:connect_retry),
          [{:tcp_connection, :disconnect}]
        }

      {:ok, %OPEN{}} ->
        {
          :ok,
          %__MODULE__{fsm | state: :idle}
          |> init_timer(:connect_retry, 0)
          |> increment_counter(:connect_retry),
          [
            {:msg, compose_msg(fsm, %NOTIFICATION{code: :cease}), :send}
          ]
        }

      {:ok, %KEEPALIVE{}} ->
        {
          :ok,
          %__MODULE__{fsm | state: :established}
          |> stop_timer(:hold_time)
          |> start_timer(:hold_time),
          []
        }
    end
  end

  defp process_event(%__MODULE__{state: :open_confirm} = fsm, _event) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:msg, compose_msg(fsm, %NOTIFICATION{code: :fsm}), :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :established} = fsm, {:start, _type, _passivity}),
    do: {:ok, fsm, []}

  defp process_event(%__MODULE__{state: :established} = fsm, {:stop, :manual}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> zero_counter(:connect_retry),
      [
        {:msg, compose_msg(fsm, %NOTIFICATION{code: :cease}), :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :established} = fsm, {:stop, :automatic}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:msg, compose_msg(fsm, %NOTIFICATION{code: :cease}), :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(%__MODULE__{state: :established} = fsm, {:timer, :hold_time, :expires}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:msg, compose_msg(fsm, %NOTIFICATION{code: :hold_timer_expired}), :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  defp process_event(
         %__MODULE__{hold_time: hold_time, state: :established} = fsm,
         {:timer, :keep_alive, :expires}
       ) do
    if hold_time > 0 do
      {
        :ok,
        fsm
        |> stop_timer(:keep_alive)
        |> init_timer(:keep_alive)
        |> start_timer(:keep_alive),
        [{:msg, compose_msg(fsm, %KEEPALIVE{}), :send}]
      }
    else
      {:ok, fsm, [{:msg, compose_msg(fsm, %KEEPALIVE{}), :send}]}
    end
  end

  defp process_event(%__MODULE__{state: :established} = fsm, {:tcp_connection, :fails}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [{:tcp_connection, :disconnect}]
    }
  end

  defp process_event(%__MODULE__{state: :established} = fsm, {:msg, msg, :recv}) do
    hold_timer_nonzero = timer_seconds(fsm, :hold_time) > 0

    case decode_msg(fsm, msg) do
      {:ok, %OPEN{}} ->
        {
          :ok,
          %__MODULE__{fsm | state: :idle}
          |> init_timer(:connect_retry, 0)
          |> increment_counter(:connect_retry),
          [
            {:msg, compose_msg(fsm, %NOTIFICATION{code: :cease}), :send},
            {:tcp_connection, :disconnect}
          ]
        }

      {:ok, %NOTIFICATION{}} ->
        {
          :ok,
          %__MODULE__{fsm | state: :idle}
          |> init_timer(:connect_retry, 0)
          |> increment_counter(:connect_retry),
          [{:tcp_connection, :disconnect}]
        }

      {:ok, %KEEPALIVE{}} when hold_timer_nonzero ->
        {
          :ok,
          fsm
          |> stop_timer(:hold_time)
          |> start_timer(:hold_time),
          []
        }

      {:ok, %KEEPALIVE{}} ->
        {:ok, fsm, []}

      {:ok, %UPDATE{} = msg} when hold_timer_nonzero ->
        {
          :ok,
          fsm
          |> stop_timer(:hold_time)
          |> start_timer(:hold_time),
          [{:msg, msg, :recv}]
        }

      {:ok, %UPDATE{} = msg} ->
        {:ok, fsm, [{:msg, msg, :recv}]}
    end
  end

  defp process_event(%__MODULE__{state: :established} = fsm, _event) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [{:msg, compose_msg(fsm, %NOTIFICATION{code: :fsm}), :send}, {:tcp_connection, :disconnect}]
    }
  end

  defp decode_msg(%__MODULE__{four_octets: four_octets} = _fsm, msg) do
    with {:ok, msg} <- Message.decode(msg, four_octets: four_octets) do
      Logger.debug("FSM received message: #{inspect(msg, pretty: true)}")
      {:ok, msg}
    end
  end

  defp compose_msg(%__MODULE__{four_octets: four_octets}, msg) do
    Message.encode(msg, four_octets: four_octets)
  end

  defp compose_open(%__MODULE__{} = fsm) do
    compose_msg(fsm, %OPEN{
      asn: fsm.asn,
      bgp_id: fsm.bgp_id,
      hold_time: fsm.hold_time,
      parameters: [
        %Capabilities{
          capabilities: [
            %Capabilities.FourOctetsASN{asn: fsm.asn},
            %Capabilities.MultiProtocol{afi: :ipv4, safi: :nlri_unicast}
          ]
        }
      ]
    })
  end

  defp process_open(%__MODULE__{} = fsm, %OPEN{} = open) do
    {four_octets, asn} =
      Enum.find_value(open.parameters, {false, open.asn}, fn
        %Capabilities{capabilities: capabilities} ->
          Enum.find_value(capabilities, fn
            %Capabilities.FourOctetsASN{asn: asn} -> {true, asn}
            _ -> nil
          end)

        _ ->
          nil
      end)

    %__MODULE__{fsm | four_octets: four_octets, internal: asn == fsm.asn}
  end

  defp increment_counter(%__MODULE__{counters: counters} = fsm, name),
    do: %__MODULE__{fsm | counters: update_in(counters, [name], &(&1 + 1))}

  defp zero_counter(%__MODULE__{counters: counters} = fsm, name),
    do: %__MODULE__{fsm | counters: update_in(counters, [name], fn _ -> 0 end)}

  defp init_timer(%__MODULE__{options: options, timers: timers} = fsm, name, value \\ nil),
    do: %__MODULE__{
      fsm
      | timers:
          update_in(timers, [name], &Timer.init(&1, value || get_in(options, [name, :secs])))
    }

  defp start_timer(%__MODULE__{timers: timers} = fsm, name),
    do: %__MODULE__{fsm | timers: update_in(timers, [name], &Timer.start(&1, name))}

  defp stop_timer(%__MODULE__{timers: timers} = fsm, name),
    do: %__MODULE__{fsm | timers: update_in(timers, [name], &Timer.stop(&1))}

  defp timer_running?(%__MODULE__{timers: timers}, name),
    do: Timer.running?(get_in(timers, [name]))

  defp timer_seconds(%__MODULE__{timers: timers}, name),
    do: Timer.seconds(get_in(timers, [name]))
end
