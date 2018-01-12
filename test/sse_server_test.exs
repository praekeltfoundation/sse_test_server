defmodule SSETestServerTest.SSEServerTest do
  use ExUnit.Case

  alias SSETestServer.SSEServer

  @stream_headers [{"content-type", "text/event-stream"}]

  def assert_response(resp=%HTTPoison.Response{}, body, status_code, headers) do
    assert %HTTPoison.Response{status_code: ^status_code, body: ^body} = resp
    for h <- headers, do: assert h in resp.headers
  end

  def assert_response(task=%Task{}, body, status_code, headers) do
    {:ok, resp} = Task.await(task)
    assert_response(resp, body, status_code, headers)
  end

  def assert_response(resp, body, status_code),
    do: assert_response(resp, body, status_code, @stream_headers)

  def event_data({ev, data}), do: "event: #{ev}\r\ndata: #{data}\r\n\r\n"
  def event_data(:keepalive), do: "\r\n"

  def assert_events(resp, events) do
    body = events |> Stream.map(&event_data/1) |> Enum.join
    assert_response(resp, body, 200)
  end

  def connect_and_collect(sse_pid, path),
    do: SSEClient.connect_and_collect("#{SSEServer.base_url(sse_pid)}#{path}")

  test "request fails for unconfigured endpoint" do
    {:ok, sse_pid} = start_supervised {SSEServer, [port: 4040]}
    task = connect_and_collect(sse_pid, "/nothing")
    assert_response(task, "", 404, [])
  end

  test "can request a stream without events or keepalives" do
    {:ok, sse_pid} = start_supervised {SSEServer, [port: 4040]}
    :ok = SSEServer.add_endpoint(sse_pid, "/events")
    task = connect_and_collect(sse_pid, "/events")
    :ok = SSEServer.end_stream(sse_pid, "/events")
    assert_response(task, "", 200)
  end

  test "can request a stream with one keepalive" do
    {:ok, sse_pid} = start_supervised {SSEServer, [port: 4040]}
    :ok = SSEServer.add_endpoint(sse_pid, "/events")
    task = connect_and_collect(sse_pid, "/events")
    :ok = SSEServer.keepalive(sse_pid, "/events")
    :ok = SSEServer.end_stream(sse_pid, "/events")
    assert_response(task, "\r\n", 200)
  end

  test "can request a stream with one event" do
    {:ok, sse_pid} = start_supervised {SSEServer, [port: 4040]}
    :ok = SSEServer.add_endpoint(sse_pid, "/events")
    task = connect_and_collect(sse_pid, "/events")
    :ok = SSEServer.event(sse_pid, "/events", "myevent", "mydata")
    :ok = SSEServer.end_stream(sse_pid, "/events")
    assert_response(task, "event: myevent\r\ndata: mydata\r\n\r\n", 200)
  end

  test "can request a stream with two events" do
    {:ok, sse_pid} = start_supervised {SSEServer, [port: 4040]}
    :ok = SSEServer.add_endpoint(sse_pid, "/events")
    task = connect_and_collect(sse_pid, "/events")
    :ok = SSEServer.event(sse_pid, "/events", "myevent", "mydata")
    :ok = SSEServer.event(sse_pid, "/events", "yourevent", "yourdata")
    :ok = SSEServer.end_stream(sse_pid, "/events")
    assert_events(task, [{"myevent", "mydata"}, {"yourevent", "yourdata"}])
  end

  test "can request a stream with events and keepalives" do
    {:ok, sse_pid} = start_supervised {SSEServer, [port: 4040]}
    :ok = SSEServer.add_endpoint(sse_pid, "/events")
    task = connect_and_collect(sse_pid, "/events")
    :ok = SSEServer.keepalive(sse_pid, "/events")
    :ok = SSEServer.event(sse_pid, "/events", "myevent", "mydata")
    :ok = SSEServer.keepalive(sse_pid, "/events")
    :ok = SSEServer.keepalive(sse_pid, "/events")
    :ok = SSEServer.event(sse_pid, "/events", "yourevent", "yourdata")
    :ok = SSEServer.end_stream(sse_pid, "/events")
    assert_events(task, [
          :keepalive,
          {"myevent", "mydata"},
          :keepalive,
          :keepalive,
          {"yourevent", "yourdata"},
        ])
  end

  test "can request a stream with multiple concurrent clients" do
    {:ok, sse_pid} = start_supervised {SSEServer, [port: 4040]}
    :ok = SSEServer.add_endpoint(sse_pid, "/events")
    task1 = connect_and_collect(sse_pid, "/events")
    :ok = SSEServer.event(sse_pid, "/events", "myevent", "mydata")
    task2 = connect_and_collect(sse_pid, "/events")
    :ok = SSEServer.event(sse_pid, "/events", "yourevent", "yourdata")
    :ok = SSEServer.end_stream(sse_pid, "/events")
    assert_events(task1, [{"myevent", "mydata"}, {"yourevent", "yourdata"}])
    assert_events(task2, [{"yourevent", "yourdata"}])
  end

  test "operations on missing endpoints fail gracefully" do
    {:ok, sse_pid} = start_supervised {SSEServer, [port: 4040]}
    :path_not_found = SSEServer.event(sse_pid, "/nothing", "myevent", "mydata")
    :path_not_found = SSEServer.keepalive(sse_pid, "/nothing")
    :path_not_found = SSEServer.end_stream(sse_pid, "/events")
  end
end
