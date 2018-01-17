defmodule SSETestServerTest.SSEServerTest do
  use ExUnit.Case

  alias SSETestServer.SSEServer

  import SSEAssertions

  def url(path), do: "#{SSEServer.base_url()}#{path}"

  def connect_and_collect(path), do: SSEClient.connect_and_collect(url(path))

  test "unconfigured endpoints 404" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    task = connect_and_collect("/nothing")
    assert_response(task, "", 404, [])
  end

  test "stream no data" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/events")
    task = connect_and_collect("/events")
    :ok = SSEServer.end_stream("/events")
    assert_response(task, "", 200)
  end

  test "stream one keepalive" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/events")
    task = connect_and_collect("/events")
    :ok = SSEServer.keepalive("/events")
    :ok = SSEServer.end_stream("/events")
    assert_response(task, "\r\n", 200)
  end

  test "stream one event" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/events")
    task = connect_and_collect("/events")
    :ok = SSEServer.event("/events", "myevent", "mydata")
    :ok = SSEServer.end_stream("/events")
    assert_response(task, "event: myevent\r\ndata: mydata\r\n\r\n", 200)
  end

  test "stream two events" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/events")
    task = connect_and_collect("/events")
    :ok = SSEServer.event("/events", "myevent", "mydata")
    :ok = SSEServer.event("/events", "yourevent", "yourdata")
    :ok = SSEServer.end_stream("/events")
    assert_events(task, [{"myevent", "mydata"}, {"yourevent", "yourdata"}])
  end

  test "stream events and keepalives" do
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

  test "stream raw bytes" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/events")
    task = connect_and_collect("/events")
    :ok = SSEServer.stream_bytes("/events", "some ")
    :ok = SSEServer.stream_bytes("/events", "bytes")
    :ok = SSEServer.keepalive("/events")
    :ok = SSEServer.stream_bytes("/events", "bye")
    :ok = SSEServer.end_stream("/events")
    assert_response(task, "some bytes\r\nbye", 200)
  end

  test "stream to multiple concurrent clients" do
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

  test "reference SSEServer by pid" do
    {:ok, pid} = SSEServer.start_link([port: 0], name: nil)
    :ok = SSEServer.add_endpoint(pid, "/events", [])
    task = SSEClient.connect_and_collect("#{SSEServer.base_url(pid)}/events")
    :ok = SSEServer.keepalive(pid, "/events")
    :ok = SSEServer.event(pid, "/events", "myevent", "mydata")
    :ok = SSEServer.end_stream(pid, "/events")
    assert_events(task, [:keepalive, {"myevent", "mydata"}])
  end

  @tag :http
  test "missing HTTP action" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/events")
    {:error, resp} = ControlClient.post(url("/events"), [])
    %{status_code: 400, body: "Missing field: action"} = resp
  end

  @tag :http
  test "bad HTTP action" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/events")
    {:error, resp} = ControlClient.post(
      "#{SSEServer.base_url()}/events", action: "brew_coffee")
    %{status_code: 400, body: "Unknown action: brew_coffee"} = resp
  end

  @tag :http
  test "stream events and keepalives over HTTP" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/events")
    task = connect_and_collect("/events")
    :ok = ControlClient.keepalive(url("/events"))
    :ok = ControlClient.event(url("/events"), "myevent", "mydata")
    :ok = ControlClient.keepalive(url("/events"))
    :ok = ControlClient.keepalive(url("/events"))
    :ok = ControlClient.event(url("/events"), "yourevent", "yourdata")
    :ok = ControlClient.end_stream(url("/events"))
    assert_events(task, [
          :keepalive,
          {"myevent", "mydata"},
          :keepalive,
          :keepalive,
          {"yourevent", "yourdata"},
        ])
  end

  @tag :http
  test "stream raw bytes over HTTP" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/events")
    task = connect_and_collect("/events")
    :ok = ControlClient.stream_bytes(url("/events"), "some ")
    :ok = ControlClient.stream_bytes(url("/events"), "bytes")
    :ok = ControlClient.keepalive(url("/events"))
    :ok = ControlClient.stream_bytes(url("/events"), "bye")
    :ok = ControlClient.end_stream(url("/events"))
    assert_response(task, "some bytes\r\nbye", 200)
  end

  @tag :http
  test "HTTP stream_bytes with missing field" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/events")
    assert {:error, %{body: "Missing field: bytes"}} =
      ControlClient.post(url("/events"), action: "stream_bytes")
  end

end
