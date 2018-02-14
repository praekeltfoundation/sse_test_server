defmodule SSETestServerTest.SSEServerTest do
  use ExUnit.Case

  alias SSETestServer.{RequestHandler,SSEHandler,SSEServer}

  import SSEAssertions

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

  test "standalone stream" do
    {:ok, sse} = start_supervised SSEServer
    SSEServer.configure_endpoint(sse, "/events", [])
    {port, _} = start_listener([
      {"/events", SSEHandler, %RequestHandler.State{sse_server: sse}},
    ])
    task = connect_and_collect(port, "/events")
    :ok = SSEServer.keepalive(sse, "/events")
    :ok = SSEServer.event(sse, "/events", "myevent", "mydata")
    :ok = SSEServer.keepalive(sse, "/events")
    :ok = SSEServer.end_stream(sse, "/events")
    assert_events(task, [:keepalive, {"myevent", "mydata"}, :keepalive])
  end

  test "standalone stream has no control API" do
    {:ok, sse} = start_supervised SSEServer
    SSEServer.configure_endpoint(sse, "/events", [])
    {port, _} = start_listener([
      {"/events", SSEHandler, %RequestHandler.State{sse_server: sse}},
    ])
    task = connect_and_collect(port, "/events")
    assert_control_err("", 405,
      ControlClient.post(url(port, "/events"), action: "keepalive"))
    :ok = SSEServer.keepalive(sse, "/events")
    :ok = SSEServer.end_stream(sse, "/events")
    assert_events(task, [:keepalive])
  end

end
