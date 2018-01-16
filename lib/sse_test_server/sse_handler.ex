defmodule SSETestServer.SSEHandler do
  @behaviour :cowboy_loop

  alias SSETestServer.SSEServer

  defmodule State do
    @enforce_keys [:path, :sse_server]
    defstruct path: nil, sse_server: nil, response_delay: nil
  end

  # TODO: Find a way to get rid of the chunk wrappers around all this stuff to
  # allow testing clients that don't handle transport-encodings transparently.

  # POST a stream action.
  def init(req=%{method: "POST"}, state) do
    {:ok, field_list, req_read} = :cowboy_req.read_urlencoded_body(req)
    fields = Map.new(field_list)
    req_resp =
      case Map.get(fields, "action") do
        "stream_bytes" ->
          SSEServer.stream_bytes(
            state.sse_server, state.path, Map.get(fields, "bytes"))
          :cowboy_req.reply(204, req_read)

        "keepalive" ->
          SSEServer.keepalive(state.sse_server, state.path)
          :cowboy_req.reply(204, req_read)

        "event" ->
          SSEServer.event(
            state.sse_server, state.path, Map.get(fields, "event"),
            Map.get(fields, "data"))
          :cowboy_req.reply(204, req_read)

        "end_stream" ->
          SSEServer.end_stream(state.sse_server, state.path)
          :cowboy_req.reply(204, req_read)

        nil ->
          :cowboy_req.reply(400, %{}, "Missing field: action", req_read)

        action ->
          :cowboy_req.reply(400, %{}, "Unknown action: #{action}", req_read)
      end
    {:ok, req_resp, state}
  end

  # GET an event-stream.
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
