defmodule SSETestServer.SSEHandler do
  @behaviour :cowboy_loop

  alias SSETestServer.HandlerUtils, as: HU
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
    req_resp = HU.process_field(
      "action", Map.new(field_list), req_read,
      &perform_action(&1, &2, req_read, state))
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

  ## Internals

  def perform_action("stream_bytes", fields, req, state) do
    HU.process_field("bytes", fields, req,
      fn bytes, _ ->
        SSEServer.stream_bytes(state.sse_server, state.path, bytes)
        HU.success(req)
      end)
  end

  def perform_action("keepalive", _fields, req, state) do
    SSEServer.keepalive(state.sse_server, state.path)
    HU.success(req)
  end

  def perform_action("event", fields, req, state) do
    HU.process_field("event", fields, req,
      fn event, _ ->
        HU.process_field("data", fields, req,
          fn data, _ ->
            SSEServer.event(state.sse_server, state.path, event, data)
            HU.success(req)
          end)
      end)
  end

  def perform_action("end_stream", _fields, req, state) do
    SSEServer.end_stream(state.sse_server, state.path)
    HU.success(req)
  end

  def perform_action(action, _fields, req, _state) do
    HU.bad_request(req, "Unknown action: #{action}")
  end

  ## Client API

  def send_info(handler, thing), do: send(handler, thing)
end
