defmodule SSETestServer.SSEServer do
  @moduledoc """
  An HTTP server for testing SSE clients.

  TODO: Document properly.
  """
  use GenServer

  alias SSETestServer.SSEHandler

  defmodule State do
    defstruct listener: nil, port: nil, sse_streams: []
  end

  ## Client

  def start_link(args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end
  def port(sse), do: GenServer.call(sse, :port)
  def base_url(sse), do: "http://localhost:#{port(sse)}"
  def event(sse, event, data), do: GenServer.call(sse, {:event, event, data})
  def keepalive(sse), do: GenServer.call(sse, :keepalive)
  def end_stream(sse), do: GenServer.call(sse, :end_stream)
  def sse_stream(sse, pid), do: GenServer.call(sse, {:sse_stream, pid})

  ## Callbacks

  def init(args) do
    # Trap exits so terminate/2 gets called reliably.
    Process.flag(:trap_exit, true)
    handler_state = %SSEHandler.State{
      stream_handler: self(),
      delay: Keyword.get(args, :response_delay),
    }
    handlers = [
      {"/v2/events", SSEHandler, handler_state},
    ]
    dispatch = :cowboy_router.compile([{:_, handlers}])
    listener_ref = make_ref()
    ranch_args = args |> Enum.filter(fn {k, _} -> k in [:port] end)
    {:ok, listener} = :cowboy.start_clear(
      listener_ref, ranch_args, %{env: %{dispatch: dispatch}})
    Process.link(listener)
    {:ok, %State{listener: listener_ref, port: :ranch.get_port(listener_ref)}}
  end

  def terminate(reason, state) do
    :cowboy.stop_listener(state.listener)
    reason
  end

  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  def handle_call({:sse_stream, pid}, _from, state) do
    new_state = %{state | sse_streams: [pid | state.sse_streams]}
    # IO.inspect {:sse_stream, new_state}
    {:reply, :ok, new_state}
  end

  def handle_call({:event, _, _}=event, _from, state) do
    Enum.each(state.sse_streams, &SSEHandler.event(&1, event))
    {:reply, :ok, state}
  end

  def handle_call(:keepalive, _from, state) do
    Enum.each(state.sse_streams, &SSEHandler.keepalive/1)
    {:reply, :ok, state}
  end

  def handle_call(:end_stream, _from, state) do
    # IO.inspect {:end_stream, state}
    Enum.each(state.sse_streams, &SSEHandler.close/1)
    {:reply, :ok, state}
  end
end
