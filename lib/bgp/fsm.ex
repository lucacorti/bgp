defmodule BGP.FSM do
  @moduledoc false

  alias BGP.FSM.Timer
  alias BGP.{Message, Session}
  alias BGP.Message.{KeepAlive, Notification, Open, Update}
  alias BGP.Message.Open.Parameter.Capabilities

  @type connection_op :: :connect | :disconnect | :reconnect
  @type msg_op :: :process | :send

  @type effect ::
          {:msg, Message.t(), msg_op()}
          | {:tcp_connection, connection_op()}

  @type start_type :: :manual | :automatic
  @type stop_type :: start_type()
  @type start_passivity :: :active | :passive
  @type connection_event :: :succeeds | :fails
  @type timer_event :: :expires

  @type event ::
          {:tcp_connection, connection_event()}
          | {:start, start_type(), start_passivity()}
          | {:stop, stop_type()}
          | {:timer, Timer.name(), timer_event()}
          | Message.t()

  @type counter :: pos_integer()
  @type state :: :idle | :active | :open_sent | :open_confirm | :established

  @type t :: %__MODULE__{
          counters: keyword(counter()),
          internal: boolean(),
          options: Session.options(),
          state: state(),
          timers: keyword(Timer.t())
        }

  @enforce_keys [:options]
  defstruct counters: [connect_retry: 0],
            internal: false,
            options: [],
            state: :idle,
            timers: [
              connect_retry: Timer.new(0),
              delay_open: Timer.new(0),
              hold_time: Timer.new(0),
              keep_alive: Timer.new(0)
            ]

  @spec new(Session.options()) :: t()
  def new(options), do: struct(__MODULE__, options: options)

  @spec event(t(), event()) :: {:ok, t(), [effect()]}
  def event(%__MODULE__{state: :idle} = fsm, {:start, _type, :active}),
    do: {
      :ok,
      %__MODULE__{fsm | state: :connect}
      |> init_timer(:connect_retry)
      |> init_timer(:delay_open)
      |> init_timer(:hold_time)
      |> init_timer(:keep_alive)
      |> zero_counter(:connect_retry)
      |> start_timer(:connect_retry),
      [{:tcp_connection, :connect}]
    }

  def event(%__MODULE__{state: :idle} = fsm, {:stop, _type}),
    do: {:ok, fsm, []}

  def event(%__MODULE__{state: :idle} = fsm, {:start, _type, :passive}),
    do: {
      :ok,
      %__MODULE__{fsm | state: :active}
      |> init_timer(:connect_retry)
      |> init_timer(:delay_open)
      |> init_timer(:hold_time)
      |> init_timer(:keep_alive)
      |> zero_counter(:connect_retry)
      |> start_timer(:connect_retry),
      []
    }

  def event(%__MODULE__{state: :idle} = fsm, _event), do: {:ok, fsm, []}

  def event(%__MODULE__{state: :connect} = fsm, {:start, _type, _passivity}),
    do: {:ok, fsm, []}

  def event(%__MODULE__{state: :connect} = fsm, {:stop, :manual}),
    do: {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> zero_counter(:connect_retry)
      |> stop_timer(:connect_retry)
      |> init_timer(:connect_retry, 0),
      [{:tcp_connection, :disconnect}]
    }

  def event(%__MODULE__{state: :connect} = fsm, {:timer, :connect_retry, :expires}),
    do: {
      :ok,
      %__MODULE__{fsm | state: :connect}
      |> start_timer(:connect_retry)
      |> stop_timer(:delay_open)
      |> init_timer(:delay_open, 0),
      [{:tcp_connection, :reconnect}]
    }

  def event(
        %__MODULE__{options: options, state: :connect} = fsm,
        {:timer, :delay_open, :expires}
      ),
      do: {
        :ok,
        %__MODULE__{fsm | state: :open_sent}
        |> init_timer(:hold_time),
        [
          {
            :msg,
            %Open{
              asn: options[:asn],
              bgp_id: options[:bgp_id],
              hold_time: options[:hold_time][:secs],
              parameters: [
                %Capabilities{
                  capabilities: [%Capabilities.MultiProtocol{afi: :ipv4, safi: :nlri_unicast}]
                }
              ]
            },
            :send
          }
        ]
      }

  def event(
        %__MODULE__{options: options, state: :connect} = fsm,
        {:tcp_connection, :succeeds}
      ) do
    if options[:delay_open][:enabled] do
      {
        :ok,
        fsm
        |> stop_timer(:connect_retry)
        |> init_timer(:connect_retry, 0)
        |> init_timer(:delay_open)
        |> start_timer(:delay_open),
        []
      }
    else
      {
        :ok,
        %__MODULE__{fsm | state: :open_sent}
        |> stop_timer(:connect_retry)
        |> init_timer(:connect_retry, 0)
        |> init_timer(:hold_time),
        [
          {
            :msg,
            %Open{
              asn: options[:asn],
              bgp_id: options[:bgp_id],
              hold_time: options[:hold_time][:secs],
              parameters: [
                %Capabilities{
                  capabilities: [%Capabilities.MultiProtocol{afi: :ipv4, safi: :nlri_unicast}]
                }
              ]
            },
            :send
          }
        ]
      }
    end
  end

  def event(%__MODULE__{state: :connect} = fsm, {:tcp_connection, :fails}) do
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

  def event(
        %__MODULE__{options: options, state: :connect} = fsm,
        %Open{hold_time: hold_time} = msg
      ) do
    fsm =
      if hold_time > 0 do
        fsm
        |> stop_timer(:keep_alive)
        |> init_timer(:keep_alive)
        |> start_timer(:keep_alive)
        |> stop_timer(:hold_time)
        |> init_timer(:hold_time, hold_time)
        |> start_timer(:hold_time)
      else
        fsm
        |> stop_timer(:keep_alive)
        |> init_timer(:keep_alive)
        |> start_timer(:keep_alive)
        |> init_timer(:hold_time)
      end

    if timer_running?(fsm, :delay_open) do
      {
        :ok,
        %__MODULE__{fsm | state: :open_confirm, internal: msg.asn == options[:asn]}
        |> stop_timer(:connect_retry)
        |> init_timer(:connect_retry, 0)
        |> stop_timer(:delay_open)
        |> init_timer(:delay_open, 0),
        [
          {
            :msg,
            %Open{
              asn: options[:asn],
              bgp_id: options[:bgp_id],
              hold_time: options[:hold_time][:secs],
              parameters: [
                %Capabilities{
                  capabilities: [%Capabilities.MultiProtocol{afi: :ipv4, safi: :nlri_unicast}]
                }
              ]
            },
            :send
          },
          {:msg, %KeepAlive{}, :send}
        ]
      }
    else
      {:ok, fsm, []}
    end
  end

  def event(%__MODULE__{state: :connect} = fsm, %Notification{
        code: :unsupported_version_number
      }) do
    fsm =
      if timer_running?(fsm, :delay_open) do
        fsm
        |> stop_timer(:delay_open)
        |> init_timer(:delay_open, 0)
      else
        fsm
        |> increment_counter(:connect_retry)
      end

    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> stop_timer(:connect_retry)
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [{:tcp_connection, :disconnect}]
    }
  end

  def event(%__MODULE__{state: :connect} = fsm, _event) do
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

  def event(%__MODULE__{state: :active} = fsm, {:start, _type, _passivity}),
    do: {:ok, fsm, []}

  def event(%__MODULE__{options: options, state: :active} = fsm, {:stop, :manual}) do
    effects =
      if options[:notification_without_open] do
        [
          {:msg, %Notification{code: :cease}, :send},
          {:tcp_connection, :disconnect}
        ]
      else
        [{:tcp_connection, :disconnect}]
      end

    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> stop_timer(:delay_open)
      |> zero_counter(:connect_retry)
      |> stop_timer(:connect_retry)
      |> init_timer(:connect_retry, 0),
      effects
    }
  end

  def event(%__MODULE__{state: :active} = fsm, {:timer, :connect_retry, :expires}) do
    {
      :ok,
      %__MODULE__{fsm | state: :connect}
      |> init_timer(:connect_retry)
      |> start_timer(:connect_retry),
      []
    }
  end

  def event(
        %__MODULE__{options: options, state: :active} = fsm,
        {:timer, :delay_open, :expires}
      ) do
    {
      :ok,
      %__MODULE__{fsm | state: :open_sent}
      |> init_timer(:connect_retry, 0)
      |> stop_timer(:delay_open)
      |> init_timer(:delay_open, 0)
      |> init_timer(:hold_time),
      [
        {
          :msg,
          %Open{
            asn: options[:asn],
            bgp_id: options[:bgp_id],
            hold_time: options[:hold_time][:secs],
            parameters: [
              %Capabilities{
                capabilities: [%Capabilities.MultiProtocol{afi: :ipv4, safi: :nlri_unicast}]
              }
            ]
          },
          :send
        }
      ]
    }
  end

  def event(%__MODULE__{options: options, state: :active} = fsm, {:tcp_connection, :succeeds}) do
    if options[:delay_open][:enabled] do
      {
        :ok,
        fsm
        |> stop_timer(:connect_retry)
        |> init_timer(:connect_retry, 0)
        |> init_timer(:delay_open),
        []
      }
    else
      {
        :ok,
        %__MODULE__{fsm | state: :open_sent}
        |> init_timer(:connect_retry, 0)
        |> init_timer(:hold_time),
        [
          {
            :msg,
            %Open{
              asn: options[:asn],
              bgp_id: options[:bgp_id],
              hold_time: options[:hold_time][:secs],
              parameters: [
                %Capabilities{
                  capabilities: [%Capabilities.MultiProtocol{afi: :ipv4, safi: :nlri_unicast}]
                }
              ]
            },
            :send
          }
        ]
      }
    end
  end

  def event(%__MODULE__{state: :active} = fsm, {:tcp_connection, :fails}),
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

  def event(
        %__MODULE__{options: options, state: :active} = fsm,
        %Open{hold_time: hold_time} = msg
      ) do
    if timer_running?(fsm, :delay_open) do
      fsm =
        if timer_seconds(fsm, :hold_time) != 0 do
          fsm
          |> stop_timer(:keep_alive)
          |> init_timer(:keep_alive)
          |> start_timer(:keep_alive)
          |> stop_timer(:hold_time)
          |> init_timer(:hold_time, hold_time)
          |> start_timer(:hold_time)
        else
          fsm
          |> init_timer(:keep_alive, 0)
          |> init_timer(:hold_time, 0)
        end

      {
        :ok,
        %__MODULE__{fsm | state: :open_confirm, internal: msg.asn == options[:asn]}
        |> stop_timer(:connect_retry)
        |> init_timer(:connect_retry, 0)
        |> stop_timer(:delay_open)
        |> init_timer(:delay_open, 0),
        [
          {
            :msg,
            %Open{
              asn: options[:asn],
              bgp_id: options[:bgp_id],
              hold_time: options[:hold_time][:secs],
              parameters: [
                %Capabilities{
                  capabilities: [%Capabilities.MultiProtocol{afi: :ipv4, safi: :nlri_unicast}]
                }
              ]
            },
            :send
          },
          {:msg, %KeepAlive{}, :send}
        ]
      }
    end
  end

  def event(%__MODULE__{state: :active} = fsm, %Notification{
        code: :unsupported_version_number
      }) do
    if timer_running?(fsm, :delay_open) do
      {
        :ok,
        %__MODULE__{fsm | state: :idle}
        |> stop_timer(:connect_retry)
        |> init_timer(:connect_retry, 0)
        |> stop_timer(:delay_open)
        |> init_timer(:delay_open, 0),
        [{:tcp_connection, :disconnect}]
      }
    else
      {
        :ok,
        %__MODULE__{fsm | state: :idle}
        |> init_timer(:connect_retry, 0)
        |> increment_counter(:connect_retry),
        [{:tcp_connection, :disconnect}]
      }
    end
  end

  def event(%__MODULE__{state: :active} = fsm, _event) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [{:tcp_connection, :disconnect}]
    }
  end

  def event(%__MODULE__{state: :open_sent} = fsm, {:start, _type, _passivity}),
    do: {:ok, fsm, []}

  def event(%__MODULE__{state: :open_sent} = fsm, {:stop, :manual}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> zero_counter(:connect_retry),
      [
        {:msg, %Notification{code: :cease}, :send}
      ]
    }
  end

  def event(%__MODULE__{state: :open_sent} = fsm, {:stop, :automatic}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:msg, %Notification{code: :cease}, :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  def event(%__MODULE__{state: :open_sent} = fsm, {:timer, :hold_time, :expires}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:msg, %Notification{code: :hold_timer_expired}, :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  def event(%__MODULE__{state: :open_sent} = fsm, {:tcp_connection, :fails}) do
    {
      :ok,
      %__MODULE__{fsm | state: :active}
      |> stop_timer(:connect_retry)
      |> start_timer(:connect_retry),
      [{:tcp_connection, :disconnect}]
    }
  end

  def event(
        %__MODULE__{options: options, state: :open_sent} = fsm,
        %Open{hold_time: hold_time} = msg
      ) do
    fsm =
      if hold_time > 0 do
        fsm
        |> stop_timer(:keep_alive)
        |> init_timer(:keep_alive)
        |> start_timer(:keep_alive)
        |> stop_timer(:hold_time)
        |> init_timer(:hold_time, hold_time)
        |> start_timer(:hold_time)
      else
        fsm
      end

    {
      :ok,
      %__MODULE__{fsm | state: :open_confirm, internal: msg.asn == options[:asn]}
      |> init_timer(:delay_open, 0)
      |> init_timer(:connect_retry, 0)
      |> stop_timer(:keep_alive),
      [
        {:msg, %KeepAlive{}, :send}
      ]
    }
  end

  def event(%__MODULE__{state: :open_sent} = fsm, %Notification{
        code: :unsupported_version_number
      }) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0),
      [{:tcp_connection, :disconnect}]
    }
  end

  def event(%__MODULE__{state: :open_sent} = fsm, _event) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:msg, %Notification{code: :fsm}, :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  def event(%__MODULE__{state: :open_confirm} = fsm, {:start, _type, _passivity}),
    do: {:ok, fsm, []}

  def event(%__MODULE__{state: :open_confirm} = fsm, {:stop, :manual}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> zero_counter(:connect_retry),
      [
        {:msg, %Notification{code: :cease}, :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  def event(%__MODULE__{state: :open_confirm} = fsm, {:stop, :automatic}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:msg, %Notification{code: :cease}, :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  def event(%__MODULE__{state: :open_confirm} = fsm, {:timer, :hold_time, :expires}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:msg, %Notification{code: :hold_timer_expired}, :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  def event(%__MODULE__{state: :open_confirm} = fsm, {:timer, :keep_alive, :expires}) do
    {
      :ok,
      fsm
      |> stop_timer(:keep_alive)
      |> init_timer(:keep_alive)
      |> start_timer(:keep_alive),
      [
        {:msg, %KeepAlive{}, :send}
      ]
    }
  end

  def event(%__MODULE__{state: :open_confirm} = fsm, {:tcp_connection, :fails}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [{:tcp_connection, :disconnect}]
    }
  end

  def event(%__MODULE__{state: :open_confirm} = fsm, %Notification{
        code: :unsupported_version_number
      }) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0),
      [{:tcp_connection, :disconnect}]
    }
  end

  def event(%__MODULE__{state: :open_confirm} = fsm, %Notification{}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [{:tcp_connection, :disconnect}]
    }
  end

  def event(%__MODULE__{state: :open_confirm} = fsm, %Open{}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:msg, %Notification{code: :cease}, :send}
      ]
    }
  end

  def event(%__MODULE__{state: :open_confirm} = fsm, %KeepAlive{}) do
    {
      :ok,
      %__MODULE__{fsm | state: :established}
      |> stop_timer(:hold_time)
      |> start_timer(:hold_time),
      []
    }
  end

  def event(%__MODULE__{state: :open_confirm} = fsm, _event) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:msg, %Notification{code: :fsm}, :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  def event(%__MODULE__{state: :established} = fsm, {:start, _type, _passivity}),
    do: {:ok, fsm, []}

  def event(%__MODULE__{state: :established} = fsm, {:stop, :manual}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> zero_counter(:connect_retry),
      [
        {:msg, %Notification{code: :cease}, :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  def event(%__MODULE__{state: :established} = fsm, {:stop, :automatic}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:msg, %Notification{code: :cease}, :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  def event(%__MODULE__{state: :established} = fsm, {:timer, :hold_time, :expires}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:msg, %Notification{code: :hold_timer_expired}, :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  def event(
        %__MODULE__{state: :established} = fsm,
        {:timer, :keep_alive, :expires}
      ) do
    fsm =
      if timer_seconds(fsm, :hold_time) > 0 do
        fsm
        |> stop_timer(:keep_alive)
        |> init_timer(:keep_alive)
        |> start_timer(:keep_alive)
      else
        fsm
      end

    {
      :ok,
      fsm,
      [
        {:msg, %KeepAlive{}, :send}
      ]
    }
  end

  def event(%__MODULE__{state: :established} = fsm, %Open{}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [
        {:msg, %Notification{code: :cease}, :send},
        {:tcp_connection, :disconnect}
      ]
    }
  end

  def event(%__MODULE__{state: :established} = fsm, {:tcp_connection, :fails}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [{:tcp_connection, :disconnect}]
    }
  end

  def event(%__MODULE__{state: :established} = fsm, %Notification{}) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [{:tcp_connection, :disconnect}]
    }
  end

  def event(%__MODULE__{state: :established} = fsm, %KeepAlive{}) do
    fsm =
      if timer_seconds(fsm, :hold_time) > 0 do
        fsm
        |> stop_timer(:hold_time)
        |> start_timer(:hold_time)
      else
        fsm
      end

    {:ok, fsm, []}
  end

  def event(%__MODULE__{state: :established} = fsm, %Update{} = msg) do
    fsm =
      if timer_seconds(fsm, :hold_time) > 0 do
        fsm
        |> stop_timer(:hold_time)
        |> start_timer(:hold_time)
      else
        fsm
      end

    {:ok, fsm, [{:msg, msg, :process}]}
  end

  def event(%__MODULE__{state: :established} = fsm, _event) do
    {
      :ok,
      %__MODULE__{fsm | state: :idle}
      |> init_timer(:connect_retry, 0)
      |> increment_counter(:connect_retry),
      [{:msg, %Notification{code: :fsm}, :send}, {:tcp_connectio, :disconnect}]
    }
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
