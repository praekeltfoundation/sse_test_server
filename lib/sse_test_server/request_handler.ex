defmodule SSETestServer.RequestHandler do

  defmodule Utils do
    defmacro __using__([]) do
      quote do
        alias SSETestServer.SSEServer

        defp when_exists(req, state, fun) do
          case SSEServer.get_endpoint(state.sse_server, req.path) do
            {:ok, endpoint} -> fun.(endpoint)
            :error -> {:ok, :cowboy_req.reply(404, req), state}
          end
        end

        defp success(req, :ok), do: :cowboy_req.reply(204, req)

        defp bad_request(req, msg), do: :cowboy_req.reply(400, %{}, msg, req)
      end
    end
  end

  @behaviour :cowboy_handler

  alias SSETestServer.{PostHandler, PutHandler, SSEHandler}

  defmodule State do
    @enforce_keys [:sse_server]
    defstruct sse_server: nil, path: nil
  end

  def init(req = %{method: "PUT"}, state), do: {PutHandler, req, state}

  def init(req = %{method: "GET"}, state), do: {SSEHandler, req, state}

  def init(req = %{method: "POST"}, state), do: {PostHandler, req, state}

end
