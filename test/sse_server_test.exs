defmodule SSETestServerTest.SSEServerTest do
  use ExUnit.Case

  alias SSETestServer.SSEServer

  import SSEAssertions

  def url(path), do: "#{SSEServer.base_url()}#{path}"

  def connect_and_collect(path), do: SSEClient.connect_and_collect(url(path))

  def assert_control_err(body, code, {:error, resp}),
    do: assert_response(resp, body, code, [])

  # This value is used for tests that measure responsese delays. The response
  # time (on my machine, at least) with no configured delay is consistently
  # under 100ms. I chose 250ms here as a balance between incorrect results and
  # waiting too long.
  @delay_ms 250

  test "unconfigured endpoints 404" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    task = connect_and_collect("/nothing")
    assert_response(task, "", 404, [])
  end

  test "stream missing accept header" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/events")
    {:ok, resp} = HTTPoison.get(url("/events"))
    assert_response(resp, "", 406, [])
  end

  test "stream bad accept header" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/events")
    {:ok, resp} = HTTPoison.get(url("/events"), %{"Accept" => "text/html"})
    assert_response(resp, "", 406, [])
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

  test "stream to multiple clients on different endpoints" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/events1")
    :ok = SSEServer.add_endpoint("/events2")
    task1 = connect_and_collect("/events1")
    task2 = connect_and_collect("/events2")
    :ok = SSEServer.event("/events1", "myevent", "mydata")
    :ok = SSEServer.event("/events2", "yourevent", "yourdata")
    :ok = SSEServer.end_stream("/events1")
    :ok = SSEServer.end_stream("/events2")
    assert_events(task1, [{"myevent", "mydata"}])
    assert_events(task2, [{"yourevent", "yourdata"}])
  end

  test "an endpoint that is a prefix of another endpoint" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/events")
    :ok = SSEServer.add_endpoint("/events/more")
    task1 = connect_and_collect("/events")
    task2 = connect_and_collect("/events/more")
    :ok = SSEServer.event("/events", "myevent", "mydata")
    :ok = SSEServer.event("/events/more", "yourevent", "yourdata")
    :ok = SSEServer.end_stream("/events")
    :ok = SSEServer.end_stream("/events/more")
    assert_events(task1, [{"myevent", "mydata"}])
    assert_events(task2, [{"yourevent", "yourdata"}])
  end

  test "operations on missing endpoints fail gracefully" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :path_not_found = SSEServer.event("/nothing", "myevent", "mydata")
    :path_not_found = SSEServer.keepalive("/nothing")
    :path_not_found = SSEServer.end_stream("/events")
  end

  test "configurable response delay" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = SSEServer.add_endpoint("/delayed_events", response_delay: @delay_ms)
    :ok = SSEServer.add_endpoint("/events")

    # Delayed endpoint.
    de0 = Time.utc_now()
    detask = connect_and_collect("/delayed_events")
    de1 = Time.utc_now()
    :ok = SSEServer.end_stream("/delayed_events")
    assert_response(detask, "", 200)
    assert Time.diff(de1, de0, :milliseconds) >= @delay_ms

    # Non-delayed endpoint as a control.
    e0 = Time.utc_now()
    etask = connect_and_collect("/events")
    e1 = Time.utc_now()
    :ok = SSEServer.end_stream("/events")
    assert_response(etask, "", 200)
    assert Time.diff(e1, e0, :milliseconds) < @delay_ms
  end

  test "reconfigure endpoint" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}

    # Start with no configured delay.
    :ok = SSEServer.add_endpoint("/events")
    t1_0 = Time.utc_now()
    task1 = connect_and_collect("/events")
    t1_1 = Time.utc_now()
    assert Time.diff(t1_1, t1_0, :milliseconds) < @delay_ms

    # Reconfigure to add a response delay.
    :ok = SSEServer.add_endpoint("/events", response_delay: @delay_ms)
    t2_0 = Time.utc_now()
    task2 = connect_and_collect("/events")
    t2_1 = Time.utc_now()
    assert Time.diff(t2_1, t2_0, :milliseconds) >= @delay_ms

    # Send an event and confirm that both connected clients receive it.
    :ok = SSEServer.event("/events", "myevent", "mydata")
    :ok = SSEServer.end_stream("/events")
    assert_events(task1, [{"myevent", "mydata"}])
    assert_events(task2, [{"myevent", "mydata"}])
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

  @tag :http_api
  test "create endpoint over HTTP" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = ControlClient.add_endpoint(url("/events"))
    task = connect_and_collect("/events")
    :ok = ControlClient.end_stream(url("/events"))
    assert_response(task, "", 200)
  end

  @tag :http_api
  test "create endpoint with response delay over HTTP" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = ControlClient.add_endpoint(
      url("/delayed_events"), response_delay: @delay_ms)
    :ok = ControlClient.add_endpoint(url("/events"))

    # Delayed endpoint.
    de0 = Time.utc_now()
    detask = connect_and_collect("/delayed_events")
    de1 = Time.utc_now()
    :ok = ControlClient.end_stream(url("/delayed_events"))
    assert_response(detask, "", 200)
    assert Time.diff(de1, de0, :milliseconds) >= @delay_ms

    # Non-delayed endpoint as a control.
    e0 = Time.utc_now()
    etask = connect_and_collect("/events")
    e1 = Time.utc_now()
    :ok = ControlClient.end_stream(url("/events"))
    assert_response(etask, "", 200)
    assert Time.diff(e1, e0, :milliseconds) < @delay_ms
  end

  @tag :http_api
  test "missing HTTP action" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = ControlClient.add_endpoint(url("/events"))
    assert_control_err("Missing field: action", 400,
      ControlClient.post(url("/events"), []))
  end

  @tag :http_api
  test "bad HTTP action" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = ControlClient.add_endpoint(url("/events"))
    assert_control_err("Unknown action: brew_coffee", 400,
      ControlClient.post(url("/events"), action: "brew_coffee"))
  end

  @tag :http_api
  test "stream action on missing endpoint" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    assert_control_err("", 404,
      ControlClient.post(url("/nothing"), action: "keepalive"))
  end

  @tag :http_api
  test "stream events and keepalives over HTTP" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = ControlClient.add_endpoint(url("/events"))
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

  @tag :http_api
  test "HTTP event with missing fields" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = ControlClient.add_endpoint(url("/events"))
    assert_control_err("Missing field: data", 400,
      ControlClient.post(url("/events"), action: "event", event: "myevent"))
    assert_control_err("Missing field: event", 400,
      ControlClient.post(url("/events"), action: "event", data: "mydata"))
    assert_control_err("Missing field: event", 400,
      ControlClient.post(url("/events"), action: "event"))
  end

  @tag :http_api
  test "stream raw bytes over HTTP" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = ControlClient.add_endpoint(url("/events"))
    task = connect_and_collect("/events")
    :ok = ControlClient.stream_bytes(url("/events"), "some ")
    :ok = ControlClient.stream_bytes(url("/events"), "bytes")
    :ok = ControlClient.keepalive(url("/events"))
    :ok = ControlClient.stream_bytes(url("/events"), "bye")
    :ok = ControlClient.end_stream(url("/events"))
    assert_response(task, "some bytes\r\nbye", 200)
  end

  @tag :http_api
  test "HTTP stream_bytes with missing field" do
    {:ok, _} = start_supervised {SSEServer, [port: 0]}
    :ok = ControlClient.add_endpoint(url("/events"))
    assert_control_err("Missing field: bytes", 400,
      ControlClient.post(url("/events"), action: "stream_bytes"))
  end

end
