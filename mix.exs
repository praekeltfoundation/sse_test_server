defmodule SSETestServer.Mixfile do
  use Mix.Project

  def project do
    [
      app: :sse_test_server,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {SSETestServer.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:conform, "~> 2.2"},
      {:cowboy, "~> 2.1"},
      # 2017-12-13: The latest hackney release (1.10.1) has a bug in async
      # request cleanup: https://github.com/benoitc/hackney/issues/447 The
      # partial fix in master leaves us with a silent deadlock, so for now
      # we'll use an earlier version.
      {:hackney, "~> 1.9.0", only: :test},
      {:httpoison, "~> 0.13", only: :test},
    ]
  end
end
