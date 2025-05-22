defmodule Phreak.MixProject do
  use Mix.Project

  def project do
    [
      app: :phreak,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix]],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: ["coveralls.html": :test]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Phreak.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # set-oriented propagations
      {:gen_stage, "~> 1.2"},
      # fast option validation
      {:nimble_options, "~> 1.0"},
      # JSON parsing
      {:jason, "~> 1.4"},
      # benchmarking
      {:benchee, "~> 1.2", only: :dev},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
