defmodule SSETestServer.PostHandler do

  use SSETestServer.RequestHandler.Base

  @behaviour :cowboy_handler

  def init(req = %{method: "POST"}, state) do
    when_exists(req, state, fn _ ->
      {:ok, field_list, req_read} = :cowboy_req.read_urlencoded_body(req)
      handle_action(Map.new(field_list), req_read, state)
    end)
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

end
