defmodule SSETestServer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  defp get_config(key), do: Application.fetch_env!(:sse_test_server, key)

  def start(_type, _args) do
    args = [port: get_config(:port)]
    children = [
      {SSETestServer.SSEListener, args}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SSETestServer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
