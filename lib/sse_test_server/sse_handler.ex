defmodule SSETestServer.SSEHandler do
  @moduledoc """
  SSE stream handler.

  TODO: Find a way to get rid of the chunk wrappers around all this stuff to
  allow testing clients that don't handle transport-encodings transparently.
  """

  use SSETestServer.RequestHandler.Base

  @behaviour :cowboy_loop

  defmodule StreamOpts do
    defstruct response_delay: 0
  end

  defmodule State do
    @enforce_keys [:path, :sse_server]
    defstruct path: nil, sse_server: nil, opts: %StreamOpts{}

    def new(path, sse_server, opts) do
      stream_opts = struct!(StreamOpts, opts)
      %__MODULE__{path: path, sse_server: sse_server, opts: stream_opts}
    end
  end

  def init(req = %{method: "GET"}, state) do
    when_exists(req, state, fn endpoint ->
      case :cowboy_req.parse_header("accept", req) do
        [{{"text", "event-stream", _}, _, _}] ->
          handle_sse_stream(req, state, endpoint.stream_state)
        _ -> {:ok, :cowboy_req.reply(406, req), state}
      end
    end)
  end

  # Reject non-GET methods with a 405.
  def init(req, state) do
    {:ok, :cowboy_req.reply(405, req), state}
  end

  def handle_sse_stream(req, state, stream_state = %{opts: opts}) do
    :ok = SSEServer.sse_stream(state.sse_server, req.path, self())
    if opts.response_delay > 0, do: Process.sleep(opts.response_delay)
    req_resp = :cowboy_req.stream_reply(
      200, %{"content-type" => "text/event-stream"}, req)
    {:cowboy_loop, req_resp, stream_state}
  end

  def info({:stream_bytes, bytes}, req, state) do
    :ok = :cowboy_req.stream_body(bytes, :nofin, req)
    {:ok, req, state}
  end

  def info(:close, req, state), do: {:stop, req, state}

  def send_info(handler, thing), do: send(handler, thing)

end
