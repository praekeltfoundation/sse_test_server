defmodule SSETestServer.SSEListener do
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

  alias SSETestServer.{RequestHandler, SSEServer}

  defmodule State do
    @enforce_keys [:listener, :port, :sse_server]
    defstruct listener: nil, port: nil, sse_server: nil

    def new(listener, port, sse_server),
      do: %__MODULE__{listener: listener, port: port, sse_server: sse_server}
  end

  ## Client API

  def start_link(args, opts \\ [name: :sse_test_server]),
    do: GenServer.start_link(__MODULE__, args, opts)

  def port(ssel \\ :sse_test_server), do: GenServer.call(ssel, :port)
  def base_url(ssel \\ :sse_test_server), do: "http://localhost:#{port(ssel)}"

  # We can't default both `ssel` and `handler_opts`, so the latter is required
  # if the former is provided.
  def configure_endpoint(ssel, path, handler_opts),
    do: GenServer.call(ssel, {:sse, {:configure_endpoint, path, handler_opts}})

  def configure_endpoint(path, handler_opts \\ []),
    do: configure_endpoint(:sse_test_server, path, handler_opts)

  def event(ssel \\ :sse_test_server, path, event, data),
    do: GenServer.call(ssel, {:sse, {:event, path, event, data}})

  def keepalive(ssel \\ :sse_test_server, path),
    do: GenServer.call(ssel, {:sse, {:keepalive, path}})

  def stream_bytes(ssel \\ :sse_test_server, path, bytes),
    do: GenServer.call(ssel, {:sse, {:stream_bytes, path, bytes}})

  def end_stream(ssel \\ :sse_test_server, path),
    do: GenServer.call(ssel, {:sse, {:end_stream, path}})

  ## Callbacks

  def init(args) do
    # Trap exits so terminate/2 gets called reliably.
    Process.flag(:trap_exit, true)
    {:ok, sse_server} = SSEServer.start_link(args)
    listener_ref = make_ref()
    ranch_args = args |> Enum.filter(fn {k, _} -> k in [:port] end)
    dispatch = :cowboy_router.compile(
      [{:_, [
           {:_, RequestHandler, %RequestHandler.State{sse_server: sse_server}},
         ]}])
    {:ok, listener} = :cowboy.start_clear(
      listener_ref, ranch_args, %{env: %{dispatch: dispatch}})
    Process.link(listener)
    {:ok, State.new(listener_ref, :ranch.get_port(listener_ref), sse_server)}
  end

  def terminate(reason, state) do
    :cowboy.stop_listener(state.listener)
    reason
  end

  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  def handle_call({:sse, msg}, _from, state),
    do: {:reply, GenServer.call(state.sse_server, msg), state}
end
