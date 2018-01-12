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
    # IO.inspect {:ca, caller, resp}
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
