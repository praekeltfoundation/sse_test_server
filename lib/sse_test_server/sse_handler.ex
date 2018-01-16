defmodule SSETestServer.SSEHandler do
  @behaviour :cowboy_loop

  alias SSETestServer.SSEServer

  defmodule State do
    @enforce_keys [:path, :sse_server]
    defstruct path: nil, sse_server: nil, response_delay: nil
  end

  # TODO: Find a way to get rid of the chunk wrappers around all this stuff to
  # allow testing clients that don't handle transport-encodings transparently.

  def init(req, state) do
    # state.response_delay is nil (which is falsey) or an integer (which is truthy).
    if state.response_delay, do: Process.sleep(state.response_delay)
    SSEServer.sse_stream(state.sse_server, state.path, self())
    new_req = :cowboy_req.stream_reply(
      200, %{"content-type" => "text/event-stream"}, req)
    {:cowboy_loop, new_req, state}
  end

  def info({:stream_bytes, bytes}, req, state) do
    :cowboy_req.stream_body(bytes, :nofin, req)
    {:ok, req, state}
  end

  def info(:close, req, state) do
    {:stop, req, state}
  end

  ## Client API

  def send_info(handler, thing), do: send(handler, thing)
end
