defmodule SSETestServer.RequestHandler do
  @moduledoc """
  HTTP request handler for everything.

  TODO: Find a way to get rid of the chunk wrappers around all this stuff to
  allow testing clients that don't handle transport-encodings transparently.
  """

  @behaviour :cowboy_loop

  alias SSETestServer.SSEServer

  defmodule State do
    @enforce_keys [:sse_server]
    defstruct sse_server: nil, path: nil
  end

  defmodule StreamOpts do
    defstruct response_delay: 0
  end

  defmodule StreamState do
    @enforce_keys [:path, :sse_server]
    defstruct path: nil, sse_server: nil, opts: %StreamOpts{}

    def new(path, sse_server, opts) do
      stream_opts = struct!(StreamOpts, opts)
      %__MODULE__{path: path, sse_server: sse_server, opts: stream_opts}
    end
  end

  def init(req = %{method: "PUT"}, state) do
    {:ok, field_list, req_read} = :cowboy_req.read_urlencoded_body(req)
    handle_put_endpoint(Map.new(field_list), req_read, state)
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

  def init(req = %{method: "POST"}, state) do
    when_exists(req, state, fn _ ->
      {:ok, field_list, req_read} = :cowboy_req.read_urlencoded_body(req)
      handle_action(Map.new(field_list), req_read, state)
    end)
  end

  def handle_sse_stream(req, state, stream_state = %{opts: opts}) do
    :ok = SSEServer.sse_stream(state.sse_server, req.path, self())
    if opts.response_delay > 0, do: Process.sleep(opts.response_delay)
    req_resp = :cowboy_req.stream_reply(
      200, %{"content-type" => "text/event-stream"}, req)
    {:cowboy_loop, req_resp, stream_state}
  end

  defp when_exists(req, state, fun) do
    case SSEServer.get_endpoint(state.sse_server, req.path) do
      {:ok, endpoint} -> fun.(endpoint)
      :error -> {:ok, :cowboy_req.reply(404, req), state}
    end
  end

  defp handle_put_endpoint(fields, req, state) do
    handler_opts =
      [fn -> get_handler_opt(fields, :response_delay, &String.to_integer/1) end]
      |> Enum.flat_map(&apply(&1, []))
    SSEServer.configure_endpoint(state.sse_server, req.path, handler_opts)
    {:ok, :cowboy_req.reply(201, req), state}
  end

  defp handle_action(fields, req, state) do
    req_resp = process_field(
      "action", fields, req, &perform_action(&1, &2, req, state))
    {:ok, req_resp, state}
  end

  defp perform_action("stream_bytes", fields, req, state) do
    process_field("bytes", fields, req,
      fn bytes, _ ->
        success(req, SSEServer.stream_bytes(state.sse_server, req.path, bytes))
      end)
  end

  defp perform_action("keepalive", _fields, req, state),
    do: success(req, SSEServer.keepalive(state.sse_server, req.path))

  defp perform_action("event", fields, req, state) do
    process_fields(["event", "data"], fields, req,
      fn [event, data], _ ->
        success(req, SSEServer.event(state.sse_server, req.path, event, data))
      end)
  end

  defp perform_action("end_stream", _fields, req, state),
    do: success(req, SSEServer.end_stream(state.sse_server, req.path))

  defp perform_action(action, _fields, req, _state),
    do: bad_request(req, "Unknown action: #{action}")

  defp get_handler_opt(fields, opt, transform) do
    case Map.fetch(fields, to_string(opt)) do
      {:ok, value} -> [{opt, transform.(value)}]
      :error -> []
    end
  end

  defp success(req, :ok), do: :cowboy_req.reply(204, req)

  defp bad_request(req, msg), do: :cowboy_req.reply(400, %{}, msg, req)

  defp process_field(field, fields, req, fun) do
    case Map.pop(fields, field) do
      {nil, _} -> bad_request(req, "Missing field: #{field}")
      {value, remaining_fields} -> fun.(value, remaining_fields)
    end
  end

  defp process_fields(field_names, fields, req, fun),
    do: process_fields(field_names, [], fields, req, fun)

  defp process_fields([], values, fields, _req, fun),
    do: fun.(Enum.reverse(values), fields)

  defp process_fields([field | field_names], values, fields, req, fun) do
    process_field(field, fields, req,
      fn value, new_fields ->
        process_fields(field_names, [value | values], new_fields, req, fun)
      end)
  end

  # Stream handler

  def info({:stream_bytes, bytes}, req, state) do
    :ok = :cowboy_req.stream_body(bytes, :nofin, req)
    {:ok, req, state}
  end

  def info(:close, req, state), do: {:stop, req, state}

  def send_info(handler, thing), do: send(handler, thing)

end
