defmodule BGP.Server do
  @moduledoc false

  use Supervisor

  alias BGP.Prefix

  @type t :: module()

  @options_schema NimbleOptions.new!(
                    asn: [
                      doc: "Server Autonomous System Number.",
                      type: :pos_integer,
                      required: true
                    ],
                    bgp_id: [
                      doc: "Server BGP ID, IP address as `:string`.",
                      type: {:custom, Prefix, :parse, []},
                      required: true
                    ],
                    peers: [
                      doc: "List peer configurations",
                      type: {:list, :keyword_list},
                      default: []
                    ]
                  )

  defmacro __using__(otp_app: otp_app) when is_atom(otp_app) do
    quote do
      @__otp_app__ unquote(otp_app)
      def __otp_app__, do: @__otp_app__
    end
  end

  defmacro __using__(_args),
    do: raise("You must pass a module name to #{__MODULE__} :otp_app option")

  def child_spec([server: server] = opts) do
    %{id: server, type: :supervisor, start: {__MODULE__, :start_link, [opts]}}
  end

  @spec start_link(keyword) :: Supervisor.on_start()
  def start_link(server: server) do
    options =
      server
      |> get_config()
      |> Keyword.put(:server, server)

    Supervisor.start_link(__MODULE__, options, name: server)
  end

  @spec get_config(t()) :: keyword()
  def get_config(server) do
    server.__otp_app__
    |> Application.get_env(server, [])
    |> NimbleOptions.validate!(@options_schema)
  end

  @spec get_config(t(), atom()) :: keyword()
  def get_config(server, key) do
    server
    |> get_config()
    |> Keyword.get(key)
  end

  @impl Supervisor
  def init(args) do
    common = Keyword.take(args, [:server])

    peers =
      Enum.map(args[:peers], fn peer -> {BGP.Server.Session, Keyword.merge(peer, common)} end)

    Supervisor.init(peers, strategy: :one_for_all)
  end
end
