defmodule SNMPSimEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :snmp_sim_ex,
      version: "0.1.1",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {SNMPSimEx.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.9", optional: true},
      {:telemetry, "~> 1.0", optional: true},
      {:snmp_ex, "~> 0.7.0", only: :test}
    ]
  end

  # Release configuration
  defp releases do
    [
      snmp_sim_ex: [
        version: "0.1.1",
        applications: [snmp_sim_ex: :permanent],
        steps: [:assemble, :tar],
        strip_beams: Mix.env() == :prod,
        include_executables_for: [:unix],
        include_erts: true,
      ]
    ]
  end
end
