defmodule SSETestServerTest.SSEServerTest do
  use ExUnit.Case

  alias SSETestServer.SSEServer

  def assert_response(
    resp, body, status_code, headers \\ [{"content-type", "text/event-stream"}]
  ) do
    assert %HTTPoison.Response{status_code: ^status_code, body: ^body} = resp
    for h <- headers, do: assert h in resp.headers
  end

  test "request fails for unconfigured endpoint" do
    {:ok, sse_pid} = start_supervised {SSEServer, [port: 4040]}
    path = "/nothing"
    task = SSEClient.connect_and_collect("#{SSEServer.base_url(sse_pid)}#{path}")
    {:ok, resp} = Task.await(task)
    assert_response(resp, "", 404, [])
  end

  test "can request a stream without events" do
    {:ok, sse_pid} = start_supervised {SSEServer, [port: 4040]}
    path = "/v2/events"
    SSEServer.add_endpoint(sse_pid, path)
    task = SSEClient.connect_and_collect("#{SSEServer.base_url(sse_pid)}#{path}")
    SSEServer.end_stream(sse_pid, path)
    {:ok, resp} = Task.await(task)
    assert_response(resp, "", 200)
  end

  test "can request a stream with one event" do
    {:ok, sse_pid} = start_supervised {SSEServer, [port: 4040]}
    path = "/v2/events"
    SSEServer.add_endpoint(sse_pid, path)
    task = SSEClient.connect_and_collect("#{SSEServer.base_url(sse_pid)}#{path}")
    SSEServer.event(sse_pid, path, "myevent", "mydata")
    SSEServer.end_stream(sse_pid, path)
    {:ok, resp} = Task.await(task)
    assert_response(resp, "event: myevent\r\ndata: mydata\r\n\r\n", 200)
  end

  test "can request a stream with two events" do
    {:ok, sse_pid} = start_supervised {SSEServer, [port: 4040]}
    path = "/v2/events"
    SSEServer.add_endpoint(sse_pid, path)
    task = SSEClient.connect_and_collect("#{SSEServer.base_url(sse_pid)}#{path}")
    SSEServer.event(sse_pid, path, "myevent", "mydata")
    SSEServer.event(sse_pid, path, "yourevent", "yourdata")
    SSEServer.end_stream(sse_pid, path)
    {:ok, resp} = Task.await(task)
    body = [
      "event: myevent\r\ndata: mydata\r\n\r\n",
      "event: yourevent\r\ndata: yourdata\r\n\r\n",
    ] |> Enum.join()
    assert_response(resp, body, 200)
  end
end
