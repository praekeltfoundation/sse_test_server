defmodule SSETestServer.AddHandler do

  alias SSETestServer.HandlerUtils, as: HU
  alias SSETestServer.SSEServer

  defmodule State do
    @enforce_keys [:sse_server]
    defstruct sse_server: nil
  end

  def init(req=%{method: "POST"}, state) do
    {:ok, field_list, req_read} = :cowboy_req.read_urlencoded_body(req)
    # We have to explicitly ask for the connection to be closed here, otherwise
    # the next request on this connection will use the same (now-obsolete)
    # routing table.
    # NOTE: This means that any new requests on other connections that were
    # started before this change will also see the old routing table.
    req_closing = :cowboy_req.set_resp_header("connection", "close", req_read)
    req_resp = HU.process_field(
      "action", Map.new(field_list), req_closing,
      &perform_action(&1, &2, req_closing, state))
    {:ok, req_resp, state}
  end

  # Since this is the global fallback endpoint, we need to 404 on all stream
  # requests to it.
  def init(req=%{method: "GET"}, state) do
    req_resp = :cowboy_req.reply(404, req)
    {:ok, req_resp, state}
  end

  defp perform_action("add_endpoint", fields, req, state) do
    handler_opts =
      [fn -> get_handler_opt(fields, :response_delay, &String.to_integer/1) end]
      |> Enum.flat_map(&apply(&1, []))
    SSEServer.add_endpoint(state.sse_server, req.path, handler_opts)
    HU.success(req)
  end

  defp perform_action(action, _fields, req, _state) do
    HU.bad_request(req, "Unknown action: #{action}")
  end

  defp get_handler_opt(fields, opt, transform) do
    case Map.fetch(fields, to_string(opt)) do
      {:ok, value} -> [{opt, transform.(value)}]
      :error -> []
    end
  end

end
