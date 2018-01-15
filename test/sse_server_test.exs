defmodule SSETestServerTest.SSEServerTest do
  use ExUnit.Case

  alias SSETestServer.SSEServer

  import SSEAssertions

  def connect_and_collect(path),
    do: SSEClient.connect_and_collect("#{SSEServer.base_url()}#{path}")

  test "request fails for unconfigured endpoint" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    task = connect_and_collect("/nothing")
    assert_response(task, "", 404, [])
  end

  test "can request a stream without events or keepalives" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/events")
    task = connect_and_collect("/events")
    :ok = SSEServer.end_stream("/events")
    assert_response(task, "", 200)
  end

  test "can request a stream with one keepalive" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/events")
    task = connect_and_collect("/events")
    :ok = SSEServer.keepalive("/events")
    :ok = SSEServer.end_stream("/events")
    assert_response(task, "\r\n", 200)
  end

  test "can request a stream with one event" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/events")
    task = connect_and_collect("/events")
    :ok = SSEServer.event("/events", "myevent", "mydata")
    :ok = SSEServer.end_stream("/events")
    assert_response(task, "event: myevent\r\ndata: mydata\r\n\r\n", 200)
  end

  test "can request a stream with two events" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/events")
    task = connect_and_collect("/events")
    :ok = SSEServer.event("/events", "myevent", "mydata")
    :ok = SSEServer.event("/events", "yourevent", "yourdata")
    :ok = SSEServer.end_stream("/events")
    assert_events(task, [{"myevent", "mydata"}, {"yourevent", "yourdata"}])
  end

  test "can request a stream with events and keepalives" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/events")
    task = connect_and_collect("/events")
    :ok = SSEServer.keepalive("/events")
    :ok = SSEServer.event("/events", "myevent", "mydata")
    :ok = SSEServer.keepalive("/events")
    :ok = SSEServer.keepalive("/events")
    :ok = SSEServer.event("/events", "yourevent", "yourdata")
    :ok = SSEServer.end_stream("/events")
    assert_events(task, [
          :keepalive,
          {"myevent", "mydata"},
          :keepalive,
          :keepalive,
          {"yourevent", "yourdata"},
        ])
  end

  test "can request a stream with multiple concurrent clients" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/events")
    task1 = connect_and_collect("/events")
    :ok = SSEServer.event("/events", "myevent", "mydata")
    task2 = connect_and_collect("/events")
    :ok = SSEServer.event("/events", "yourevent", "yourdata")
    :ok = SSEServer.end_stream("/events")
    assert_events(task1, [{"myevent", "mydata"}, {"yourevent", "yourdata"}])
    assert_events(task2, [{"yourevent", "yourdata"}])
  end

  test "operations on missing endpoints fail gracefully" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :path_not_found = SSEServer.event("/nothing", "myevent", "mydata")
    :path_not_found = SSEServer.keepalive("/nothing")
    :path_not_found = SSEServer.end_stream("/events")
  end

  test "configurable response delay" do
    # On my machine, the response time with no configured delay is consistently
    # under 100ms. I chose 250ms here as a balance between incorrect results
    # and waiting too long.
    delay_ms = 250

    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/delayed_events", response_delay: delay_ms)
    :ok = SSEServer.add_endpoint("/events")

    # Delayed endpoint.
    de0 = Time.utc_now()
    detask = connect_and_collect("/delayed_events")
    de1 = Time.utc_now()
    :ok = SSEServer.end_stream("/delayed_events")
    assert_response(detask, "", 200)
    assert Time.diff(de1, de0, :milliseconds) >= delay_ms

    # Non-delayed endpoint as a control.
    e0 = Time.utc_now()
    etask = connect_and_collect("/events")
    e1 = Time.utc_now()
    :ok = SSEServer.end_stream("/events")
    assert_response(etask, "", 200)
    assert Time.diff(e1, e0, :milliseconds) < delay_ms
  end

  test "can reference the SSEServer by pid" do
    {:ok, pid} = SSEServer.start_link([port: 0], name: nil)
    :ok = SSEServer.add_endpoint(pid, "/events", [])
    task = SSEClient.connect_and_collect("#{SSEServer.base_url(pid)}/events")
    :ok = SSEServer.keepalive(pid, "/events")
    :ok = SSEServer.event(pid, "/events", "myevent", "mydata")
    :ok = SSEServer.end_stream(pid, "/events")
    assert_events(task, [:keepalive, {"myevent", "mydata"}])
  end
end
