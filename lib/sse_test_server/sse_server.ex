defmodule SSETestServer.SSEServer do
  @moduledoc """
  An HTTP server for testing SSE clients.

  TODO: Document properly.
  """
  use GenServer

  alias SSETestServer.SSEHandler

  defmodule State do
    defstruct listener: nil, port: nil, sse_endpoints: %{}
  end

  defmodule SSEEndpoint do
    @enforce_keys [:path]
    defstruct path: nil, handler_state: nil, streams: []

    def new(path, handler_opts \\ []) do
      handler_state = %SSEHandler.State{path: path, sse_server: self()}
      %__MODULE__{
        path: path,
        handler_state: Map.merge(handler_state, Map.new(handler_opts)),
      }
    end

    def to_handler(endpoint),
      do: {endpoint.path, SSEHandler, endpoint.handler_state}
  end

  ## Client API

  def start_link(args, opts \\ [name: :sse_test_server]) do
    GenServer.start_link(__MODULE__, args, opts)
  end
  def port(sse \\ :sse_test_server), do: GenServer.call(sse, :port)
  def base_url(sse \\ :sse_test_server), do: "http://localhost:#{port(sse)}"

  def add_endpoint(sse \\ :sse_test_server, path, handler_opts \\ []),
    do: GenServer.call(sse, {:add_endpoint, path, handler_opts})

  def event(sse \\ :sse_test_server, path, event, data),
    do: GenServer.call(sse, {:event, path, event, data})

  def keepalive(sse \\ :sse_test_server, path),
    do: GenServer.call(sse, {:keepalive, path})

  def end_stream(sse \\ :sse_test_server, path),
    do: GenServer.call(sse, {:end_stream, path})

  ## Internal client API

  def sse_stream(sse, path, pid),
    do: GenServer.call(sse, {:sse_stream, path, pid})

  ## Callbacks

  def init(args) do
    # Trap exits so terminate/2 gets called reliably.
    Process.flag(:trap_exit, true)
    listener_ref = make_ref()
    ranch_args = args |> Enum.filter(fn {k, _} -> k in [:port] end)
    dispatch = :cowboy_router.compile([{:_, []}])
    {:ok, listener} = :cowboy.start_clear(
      listener_ref, ranch_args, %{env: %{dispatch: dispatch}})
    Process.link(listener)
    {:ok, %State{listener: listener_ref, port: :ranch.get_port(listener_ref)}}
  end

  defp set_endpoint(state, endpoint) do
    new_endpoints = Map.put(state.sse_endpoints, endpoint.path, endpoint)
    update_env(%State{state | sse_endpoints: new_endpoints})
  end

  defp update_env(state) do
    handlers =
      state.sse_endpoints
      |> Map.values
      |> Enum.map(&SSEEndpoint.to_handler/1)
      |> Enum.sort
    dispatch = :cowboy_router.compile([{:_, handlers}])
    :cowboy.set_env(state.listener, :dispatch, dispatch)
    state
  end

  def terminate(reason, state) do
    :cowboy.stop_listener(state.listener)
    reason
  end

  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  def handle_call({:sse_stream, path, pid}, _from, state) do
    endpoint = Map.fetch!(state.sse_endpoints, path)
    new_endpoint = %{endpoint | streams: [pid | endpoint.streams]}
    new_endpoints = Map.put(state.sse_endpoints, path, new_endpoint)
    new_state = %{state | sse_endpoints: new_endpoints}
    # IO.inspect {:sse_stream, new_state}
    {:reply, :ok, new_state}
  end

  def handle_call({:add_endpoint, path, handler_opts}, _from, state) do
    new_endpoint = SSEEndpoint.new(path, handler_opts)
    {:reply, :ok, set_endpoint(state, new_endpoint)}
  end

  def handle_call({:event, path, event, data}, _from, state) do
    case Map.fetch(state.sse_endpoints, path) do
      :error -> {:reply, :path_not_found, state}
      {:ok, %{streams: streams}} ->
        Enum.each(streams, &SSEHandler.event(&1, {:event, event, data}))
        {:reply, :ok, state}
    end
  end

  def handle_call({:keepalive, path}, _from, state) do
    case Map.fetch(state.sse_endpoints, path) do
      :error -> {:reply, :path_not_found, state}
      {:ok, %{streams: streams}} ->
        Enum.each(streams, &SSEHandler.keepalive/1)
        {:reply, :ok, state}
    end
  end

  def handle_call({:end_stream, path}, _from, state) do
    # IO.inspect {:end_stream, state}
    case Map.fetch(state.sse_endpoints, path) do
      :error -> {:reply, :path_not_found, state}
      {:ok, %{streams: streams}} ->
        Enum.each(streams, &SSEHandler.close/1)
        {:reply, :ok, state}
    end
  end
end
