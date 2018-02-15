defmodule SSETestServerTest.SSEServerTest do
  use ExUnit.Case

  alias SSETestServer.SSEServer

  import SSEAssertions

  def assert_get_response(port, path, body, code) do
    {:ok, resp} = HTTPoison.get(url(port, path))
    assert_response(resp, body, code, [])
  end

  defp start_listener(path_handlers) do
    listener_ref = make_ref()
    dispatch = :cowboy_router.compile([{:_, path_handlers}])
    {:ok, _} = :cowboy.start_clear(
      listener_ref, [], %{env: %{dispatch: dispatch}})
    on_exit(fn() -> :cowboy.stop_listener(listener_ref) end)
    {:ranch.get_port(listener_ref), listener_ref}
  end

  def url(port, path), do: "http://localhost:#{port}#{path}"

  def connect_and_collect(port, path),
    do: SSEClient.connect_and_collect(url(port, path))

  test "standalone stream handler" do
    {:ok, sse} = start_supervised SSEServer
    {port, _} = start_listener([
      SSEServer.configure_endpoint_handler(sse, "/events", []),
    ])
    # We only handle requests on the configured path.
    assert_get_response(port, "/nothing", "", 404)
    assert_get_response(port, "/events", "", 406)
    # We properly serve SSE requests.
    task = connect_and_collect(port, "/events")
    :ok = SSEServer.keepalive(sse, "/events")
    :ok = SSEServer.event(sse, "/events", "myevent", "mydata")
    :ok = SSEServer.keepalive(sse, "/events")
    :ok = SSEServer.end_stream(sse, "/events")
    assert_events(task, [:keepalive, {"myevent", "mydata"}, :keepalive])
  end

  test "standalone stream has no control API" do
    {:ok, sse} = start_supervised SSEServer
    {port, _} = start_listener([
      SSEServer.configure_endpoint_handler(sse, "/events", []),
    ])
    task = connect_and_collect(port, "/events")
    assert_control_err("", 405, ControlClient.keepalive(url(port, "/events")))
    :ok = SSEServer.keepalive(sse, "/events")
    :ok = SSEServer.end_stream(sse, "/events")
    assert_events(task, [:keepalive])
  end

end
