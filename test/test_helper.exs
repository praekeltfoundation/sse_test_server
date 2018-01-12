defmodule SSEAssertions do
  @stream_headers [{"content-type", "text/event-stream"}]

  import ExUnit.Assertions, only: [assert: 1, assert: 2]

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
end

defmodule SSEClient do
  require Logger

  @sse_headers %{"Accept" => "text/event-stream"}

  def connect_and_collect(url) do
    caller = self()
    task = Task.async(fn ->
      {:ok, _} = HTTPoison.get(url, @sse_headers, stream_to: self())
      collect_async(caller, %HTTPoison.Response{body: "", request_url: url})
    end)
    receive do
      :connected -> task
    end
  end

  defp collect_async(caller, resp) do
    receive do
      # Getting the status indicates we're connected and can return the task.
      %HTTPoison.AsyncStatus{code: code} ->
        send(caller, :connected)
        collect_async(caller, %{resp | status_code: code})

      # Add the headers to the response.
      %HTTPoison.AsyncHeaders{headers: headers} ->
        collect_async(caller, %{resp | headers: headers})

      # Add a chunk of content to the body.
      %HTTPoison.AsyncChunk{chunk: chunk} ->
        collect_async(caller, %{resp | body: resp.body <> chunk})

      # We're done, return the response.
      %HTTPoison.AsyncEnd{} ->
        {:ok, resp}

      # Error! Return the reason along with the response so far.
      %HTTPoison.Error{reason: reason} ->
        IO.inspect {:ca_err, reason}
        {:error, reason, resp}

      # Unexpected message. Log and ignore.
      async_resp ->
        Logger.warn("Unexpected async response, ignoring: #{inspect async_resp}")
        IO.puts("Unexpected async response, ignoring: #{inspect async_resp}")
        collect_async(caller, resp)
    end
  end

end

# We don't start applications during tests because we don't want our own app
# running, but we do need all its dependencies running.
Application.load(:sse_test_server)
for app <- Application.spec(:sse_test_server, :applications) do
  Application.ensure_all_started(app)
end

ExUnit.start()
