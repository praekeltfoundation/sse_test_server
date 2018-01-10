defmodule SSETestServer.SSEHandler do

  alias SSETestServer.SSEServer

  defmodule State do
    @enforce_keys [:path, :sse_server]
    defstruct path: nil, sse_server: nil, delay: nil
  end

  # TODO: Find a way to get rid of the chunk wrappers around all this stuff to
  # allow testing clients that don't handle transport-encodings transparently.

  def init(req, state) do
    # state.delay is nil (which is falsey) or an integer (which is truthy).
    if state.delay, do: Process.sleep(state.delay)
    SSEServer.sse_stream(state.sse_server, state.path, self())
    new_req = :cowboy_req.stream_reply(
      200, %{"content-type" => "text/event-stream"}, req)
    {:cowboy_loop, new_req, state}
  end

  def info(:keepalive, req, state) do
    :cowboy_req.stream_body("\r\n", :nofin, req)
    {:ok, req, state}
  end

  def info({:event, event, data}, req, state) do
    ev = "event: #{event}\r\ndata: #{data}\r\n\r\n"
    :cowboy_req.stream_body(ev, :nofin, req)
    {:ok, req, state}
  end

  def info(:close, req, state) do
    {:stop, req, state}
  end

  ## Client API

  def keepalive(handler), do: send(handler, :keepalive)
  def event(handler, {:event, _, _}=event), do: send(handler, event)
  def close(handler), do: send(handler, :close)
end
