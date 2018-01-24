defmodule SSETestServerTest do
  use ExUnit.Case

  alias SSETestServer.SSEServer

  import SSEAssertions

  test "application starts properly" do
    :ok = Application.start(:sse_test_server)
    on_exit(fn -> Application.stop(:sse_test_server) end)
    :ok = SSEServer.configure_endpoint("/events")
    task = SSEClient.connect_and_collect("#{SSEServer.base_url()}/events")
    :ok = SSEServer.event("/events", "myevent", "mydata")
    :ok = SSEServer.end_stream("/events")
    assert_response(task, "event: myevent\r\ndata: mydata\r\n\r\n", 200)
  end
end
