defmodule DataStream.PoolboyWorker do
  require Logger
  alias DataStream.DownloadMd
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil)
  end

  def init(_) do
    {:ok, nil}
  end

  def handle_call({:new_link, link}, _from, state) do
    case DownloadMd.call(link) do
      {:ok, _} ->
        Logger.info('Audio processed')
        {:reply, :ok, state}

      {:error, error_message} ->
        Logger.error(error_message)
        {:reply, nil, state}
    end
  end
end
