defmodule SSETestServer.PutHandler do

  @behaviour :cowboy_sub_protocol
  @behaviour :cowboy_handler

  use SSETestServer.RequestHandler.Utils

  def upgrade(req, env, handler, handler_opts),
    do: upgrade(req, env, handler, handler_opts, nil)

  def upgrade(req, env, _handler, handler_opts, _opts),
    do: :cowboy_handler.execute(
          req, %{env | handler: __MODULE__, handler_opts: handler_opts})

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
