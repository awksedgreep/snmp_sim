defmodule SnmpSim.MixProject do
  use Mix.Project

  def project do
    [
      app: :snmp_sim,
      version: "1.0.1",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix, :eex],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_local_path: "priv/plts/dialyzer",
        plt_core_path: "priv/plts",
        ignore_warnings: ".dialyzer_ignore.exs",
        list_unused_filters: true,
        flags: [
          :error_handling,
          :underspecs,
          :unknown,
          :unmatched_returns,
          :no_return
        ]
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :snmp, :os_mon],
      mod: {SnmpSim.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:snmp_lib, git: "https://github.com/awksedgreep/snmp_lib", tag: "v1.0.1"},
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.9", optional: true},
      {:telemetry, "~> 1.0", optional: true},
      {:snmp_ex, "~> 0.7.0", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  # Release configuration
  defp releases do
    [
      snmp_sim: [
        version: "1.0.1",
        applications: [snmp_sim: :permanent],
        steps: [:assemble, :tar],
        strip_beams: Mix.env() == :prod,
        include_executables_for: [:unix],
        include_erts: true,
      ]
    ]
  end
end
