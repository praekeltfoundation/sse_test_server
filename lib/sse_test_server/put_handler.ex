defmodule SSETestServer.PutHandler do

  use SSETestServer.RequestHandler.Base

  @behaviour :cowboy_handler

  def init(req = %{method: "PUT"}, state) do
    {:ok, field_list, req_read} = :cowboy_req.read_urlencoded_body(req)
    handle_put_endpoint(Map.new(field_list), req_read, state)
  end

  defp handle_put_endpoint(fields, req, state) do
    handler_opts =
      [fn -> get_handler_opt(fields, :response_delay, &String.to_integer/1) end]
      |> Enum.flat_map(&apply(&1, []))
    SSEServer.configure_endpoint(state.sse_server, req.path, handler_opts)
    {:ok, :cowboy_req.reply(201, req), state}
  end

  defp get_handler_opt(fields, opt, transform) do
    case Map.fetch(fields, to_string(opt)) do
      {:ok, value} -> [{opt, transform.(value)}]
      :error -> []
    end
  end

end
