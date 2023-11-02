defmodule BGP.MixProject do
  use Mix.Project

  def project do
    [
      app: :bgp,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications:
        [:logger, :runtime_tools, :ssl] ++ if(Mix.env() == :dev, do: [:observer, :wx], else: []),
      mod: {BGP.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:connection, "~> 1.0"},
      {:ip, "~> 2.0"},
      {:nimble_options, "~> 1.0"},
      {:thousand_island, "~> 1.0-pre"},
      {:credo, "~> 1.0", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:ex_doc, "~> 0.26", only: :dev, runtime: false}
    ]
  end

  defp dialyzer do
    [plt_add_apps: [:mix]]
  end

  defp docs() do
    [
      name: "BGP",
      groups_for_modules: [
        "Message Types": [~r/^BGP\.Message\.(KEEPALIVE|NOTIFICATION|OPEN|ROUTEREFRESH|UPDATE)$/],
        "OPEN Capabilities": [~r/^BGP\.Message\.OPEN\.Capabilities.*/],
        "UPDATE Attributes": [~r/^BGP\.Message\.UPDATE\.Attribute.*/],
        Message: [~r/^BGP\.Message$/, ~r/^BGP\.Message\.[A-Za-z]+$/],
        "Finite State Machine": [~r/^BGP\.FSM.*$/]
      ]
    ]
  end
end
