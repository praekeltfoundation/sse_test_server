defmodule SSETestServer.SSEServer do
  @moduledoc """
  An HTTP server for testing SSE clients.

  `SSETestServer.SSEServer` manages configurable Server-Sent Event endpoints,
  where each endpoint has its own HTTP path.

  Endpoints are created and configured by calling `configure_endpoint/2` (or
  `configure_endpoint/3`). Once an endpoint exists, events and keepalives can
  be sent with `event/4` and `keepalive/2`. All connections to an endpoint can
  be closed with `end_stream/2`.

  TODO: Document HTTP API.
  """
  use GenServer

  alias SSETestServer.{RequestHandler,SSEHandler}

  defmodule State do
    defstruct sse_endpoints: %{}
  end

  defmodule SSEEndpoint do
    @enforce_keys [:path]
    defstruct path: nil, stream_state: nil, streams: []

    defp stream_state(path, opts),
      do: SSEHandler.State.new(path, self(), opts)

    def configure(path, opts, nil),
      do: configure(path, opts, %__MODULE__{path: path})

    def configure(path, opts, endpoint),
      do: %{endpoint | stream_state: stream_state(path, opts)}
  end

  ## Client API

  def start_link(args, opts \\ []),
    do: GenServer.start_link(__MODULE__, args, opts)

  def configure_endpoint(sse, path, handler_opts \\ []),
    do: GenServer.call(sse, {:configure_endpoint, path, handler_opts})

  def event(sse, path, event, data),
    do: GenServer.call(sse, {:event, path, event, data})

  def keepalive(sse, path),
    do: GenServer.call(sse, {:keepalive, path})

  def stream_bytes(sse, path, bytes),
    do: GenServer.call(sse, {:stream_bytes, path, bytes})

  def end_stream(sse, path),
    do: GenServer.call(sse, {:end_stream, path})

  def configure_endpoint_handler(sse, path, handler_opts \\ []) do
    :ok = configure_endpoint(sse, path, handler_opts)
    {path, SSEHandler, %RequestHandler.State{sse_server: sse}}
  end

  ## Internal client API

  def get_endpoint(sse, path),
    do: GenServer.call(sse, {:get_endpoint, path})

  def sse_stream(sse, path, pid),
    do: GenServer.call(sse, {:sse_stream, path, pid})

  ## Callbacks

  def init(_), do: {:ok, %State{}}

  defp update_endpoint(state, endpoint) do
    new_endpoints = Map.put(state.sse_endpoints, endpoint.path, endpoint)
    %State{state | sse_endpoints: new_endpoints}
  end

  def handle_call({:get_endpoint, path}, _from, state),
    do: {:reply, Map.fetch(state.sse_endpoints, path), state}

  def handle_call({:sse_stream, path, pid}, _from, state) do
    endpoint = Map.fetch!(state.sse_endpoints, path)
    new_endpoint = %{endpoint | streams: [pid | endpoint.streams]}
    {:reply, :ok, update_endpoint(state, new_endpoint)}
  end

  def handle_call({:configure_endpoint, path, handler_opts}, _from, state) do
    old_endpoint = Map.get(state.sse_endpoints, path)
    endpoint = SSEEndpoint.configure(path, handler_opts, old_endpoint)
    {:reply, :ok, update_endpoint(state, endpoint)}
  end

  def handle_call({:stream_bytes, path, bytes}, _from, state),
    do: send_to_handler({:stream_bytes, bytes}, path, state)

  def handle_call({:event, path, event, data}, _from, state),
    do: send_to_handler({:stream_bytes, mkevent(event, data)}, path, state)

  def handle_call({:keepalive, path}, _from, state),
    do: send_to_handler({:stream_bytes, "\r\n"}, path, state)

  def handle_call({:end_stream, path}, _from, state),
    do: send_to_handler(:close, path, state)

  defp mkevent(event, data), do: "event: #{event}\r\ndata: #{data}\r\n\r\n"

  defp send_to_handler(thing, path, state) do
    case Map.fetch(state.sse_endpoints, path) do
      :error -> {:reply, :path_not_found, state}
      {:ok, %{streams: streams}} ->
        Enum.each(streams, &SSEHandler.send_info(&1, thing))
        {:reply, :ok, state}
    end
  end
end
