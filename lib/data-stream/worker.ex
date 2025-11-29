defmodule DataStream.PoolboyWorker do
  use GenServer

  require Logger
  alias DataStream.DownloadMd

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil)
  end

  def init(_) do
    {:ok, %{processed: 0, failed: 0, succeeded: 0}}
  end

  def handle_call({:new_link, link}, _from, state) do
    start_time = System.monotonic_time(:millisecond)
    
    case DownloadMd.call(link) do
      {:ok, _} ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        Logger.info("✓ Audio processed in #{elapsed}ms")
        new_state = %{
          state 
          | processed: state.processed + 1, 
            succeeded: state.succeeded + 1
        }
        {:reply, :ok, new_state}

      {:error, error_message} ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        Logger.error("✗ Failed after #{elapsed}ms: #{error_message}")
        new_state = %{
          state 
          | processed: state.processed + 1, 
            failed: state.failed + 1
        }
        {:reply, {:error, error_message}, new_state}
    end
  end

  def handle_call(:stats, _from, state) do
    {:reply, state, state}
  end
end
