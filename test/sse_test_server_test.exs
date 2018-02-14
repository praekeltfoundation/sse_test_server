defmodule SSETestServerTest do
  use ExUnit.Case

  alias SSETestServer.SSEListener

  import SSEAssertions

  test "application starts properly" do
    :ok = Application.start(:sse_test_server)
    on_exit(fn -> Application.stop(:sse_test_server) end)
    :ok = SSEListener.configure_endpoint("/events")
    task = SSEClient.connect_and_collect("#{SSEListener.base_url()}/events")
    :ok = SSEListener.event("/events", "myevent", "mydata")
    :ok = SSEListener.end_stream("/events")
    assert_response(task, "event: myevent\r\ndata: mydata\r\n\r\n", 200)
  end
end
