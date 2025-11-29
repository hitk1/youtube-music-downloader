defmodule DataStream.Poolboy do
  @moduledoc """
  Poolboy configuration and supervision for the YouTube downloader.
  
  Pool Configuration:
  - size: 5 core workers (yt-dlp is CPU/IO bound, more workers = more system load)
  - max_overflow: 5 additional workers when demand increases
  - Total: 5-10 concurrent downloads
  """
  use Application

  require Logger

  defp poolboy_config do
    [
      name: {:local, :worker},
      worker_module: DataStream.PoolboyWorker,
      size: 5,
      max_overflow: 5
    ]
  end

  def start(_type, _args) do
    Logger.info("Starting Poolboy worker pool")
    
    children = [
      :poolboy.child_spec(:worker, poolboy_config())
    ]

    opts = [strategy: :one_for_one, name: DataStream.PoolboySupervisor]
    Supervisor.start_link(children, opts)
  end
end
