defmodule SnmpSimEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :snmp_sim_ex,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {SnmpSimEx.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:snmp_ex, "~> 0.7.0", only: :test}
    ]
  end
end
