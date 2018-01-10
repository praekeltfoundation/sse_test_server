defmodule SSETestServerTest.SSEServerTest do
  use ExUnit.Case

  alias SSETestServer.SSEServer

  def assert_response(resp, body, status_code \\ 200) do
    assert %HTTPoison.Response{status_code: ^status_code, body: ^body} = resp
    assert {"content-type", "text/event-stream"} in resp.headers
  end

  test "can request a stream without events" do
    {:ok, sse_pid} = start_supervised {SSEServer, [port: 4040]}
    task = SSEClient.connect_and_collect("#{SSEServer.base_url(sse_pid)}/v2/events")
    SSEServer.end_stream(sse_pid)
    {:ok, resp} = Task.await(task)
    assert_response(resp, "", 200)
  end

  test "can request a stream with one event" do
    {:ok, sse_pid} = start_supervised {SSEServer, [port: 4040]}
    task = SSEClient.connect_and_collect("#{SSEServer.base_url(sse_pid)}/v2/events")
    SSEServer.event(sse_pid, "myevent", "mydata")
    SSEServer.end_stream(sse_pid)
    {:ok, resp} = Task.await(task)
    assert_response(resp, "event: myevent\r\ndata: mydata\r\n\r\n", 200)
  end

  test "can request a stream with two events" do
    {:ok, sse_pid} = start_supervised {SSEServer, [port: 4040]}
    task = SSEClient.connect_and_collect("#{SSEServer.base_url(sse_pid)}/v2/events")
    SSEServer.event(sse_pid, "myevent", "mydata")
    SSEServer.event(sse_pid, "yourevent", "yourdata")
    SSEServer.end_stream(sse_pid)
    {:ok, resp} = Task.await(task)
    body = [
      "event: myevent\r\ndata: mydata\r\n\r\n",
      "event: yourevent\r\ndata: yourdata\r\n\r\n",
    ] |> Enum.join()
    assert_response(resp, body, 200)
  end
end
