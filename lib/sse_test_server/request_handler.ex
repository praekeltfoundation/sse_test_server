defmodule SSETestServer.RequestHandler do
  @moduledoc """
  HTTP request handler for everything.

  TODO: Find a way to get rid of the chunk wrappers around all this stuff to
  allow testing clients that don't handle transport-encodings transparently.
  """

  # We implement both of these behaviours, but we only delcare one of them
  # because they overlap.
  @behaviour :cowboy_rest
  # @behaviour :cowboy_loop

  alias SSETestServer.SSEServer

  defmodule State do
    @enforce_keys [:sse_server]
    defstruct sse_server: nil, path: nil
  end

  defmodule StreamState do
    @enforce_keys [:path, :sse_server]
    defstruct path: nil, sse_server: nil, response_delay: nil
  end

  def init(req, state) do
    {:cowboy_rest, req, state}
  end

  def allowed_methods(req, state),
    do: {["GET", "HEAD", "OPTIONS", "PUT", "POST"], req, state}

  def allow_missing_post(req, state), do: {false, req, state}

  def resource_exists(req, state) do
    case SSEServer.get_endpoint(state.sse_server, req.path) do
      {:ok, _} -> {true, req, state}
      :error -> {false, req, state}
    end
  end

  def content_types_provided(req, state),
    do: {[{{"text", "event-stream", :*}, :to_sse_stream}], req, state}

  def to_sse_stream(req, state) do
    {:ok, endpoint} = SSEServer.sse_stream(state.sse_server, req.path, self())
    sse_state = endpoint.handler_state
    # sse_state.response_delay is nil (falsey) or an integer (truthy).
    if sse_state.response_delay, do: Process.sleep(sse_state.response_delay)
    new_req = :cowboy_req.stream_reply(
      200, %{"content-type" => "text/event-stream"}, req)
    {{:switch_handler, :cowboy_loop}, new_req, sse_state}
  end

  def content_types_accepted(req, state),
    do: {[{{"application", "x-www-form-urlencoded", :*}, :from_form}], req, state}

  def from_form(req, state) do
    {:ok, field_list, req_read} = :cowboy_req.read_urlencoded_body(req)
    handle_action(Map.new(field_list), req_read, state)
  end

  defp handle_action(fields, req = %{method: "PUT"}, state) do
    handler_opts =
      [fn -> get_handler_opt(fields, :response_delay, &String.to_integer/1) end]
      |> Enum.flat_map(&apply(&1, []))
    SSEServer.add_endpoint(state.sse_server, req.path, handler_opts)
    {true, req, state}
  end

  defp handle_action(fields, req, state) do
    {success, req_resp} = process_field(
      "action", fields, req, &perform_action(&1, &2, req, state))
    {success, req_resp, state}
  end

  defp perform_action("stream_bytes", fields, req, state) do
    process_field("bytes", fields, req,
      fn bytes, _ ->
        SSEServer.stream_bytes(state.sse_server, req.path, bytes)
        {true, req}
      end)
  end

  defp perform_action("keepalive", _fields, req, state) do
    SSEServer.keepalive(state.sse_server, req.path)
    {true, req}
  end

  defp perform_action("event", fields, req, state) do
    process_fields(["event", "data"], fields, req,
      fn [event, data], _ ->
        SSEServer.event(state.sse_server, req.path, event, data)
        {true, req}
      end)
  end

  defp perform_action("end_stream", _fields, req, state) do
    SSEServer.end_stream(state.sse_server, req.path)
    {true, req}
  end

  defp perform_action(action, _fields, req, _state),
    do: bad_request(req, "Unknown action: #{action}")

  defp get_handler_opt(fields, opt, transform) do
    case Map.fetch(fields, to_string(opt)) do
      {:ok, value} -> [{opt, transform.(value)}]
      :error -> []
    end
  end

  defp bad_request(req, msg), do: {false, :cowboy_req.set_resp_body(msg, req)}

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

  def info(:close, req, state) do
    {:stop, req, state}
  end

  def send_info(handler, thing), do: send(handler, thing)

end
