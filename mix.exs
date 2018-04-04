defmodule SSETestServer.Mixfile do
  use Mix.Project

  def project do
    [
      app: :sse_test_server,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        "coveralls": :test,
        "coveralls.json": :test,
        "coveralls.html": :test,
      ],
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {SSETestServer.Application, []}
    ]
  end

  defp aliases, do: [
    # Don't start application for tests.
    test: "test --no-start",
  ]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:conform, "~> 2.2"},
      {:cowboy, "~> 2.2"},
      {:httpoison, "~> 0.13", only: :test},
      {:excoveralls, "~> 0.7", only: :test},
      {:distillery, "~> 1.5", runtime: :false},
    ]
  end
end
