defmodule DataStream.Poolboy do
  @moduledoc false
  use Application

  defp poolboy_config do
    [
      name: {:local, :worker},
      worker_module: DataStream.PoolboyWorker,
      size: 25,
      max_overflow: 15
    ]
  end

  def start(_type, _args) do
    children = [
      :poolboy.child_spec(:worker, poolboy_config())
    ]

    opts = [strategy: :one_for_one, name: DataStream.PoolboySupervisor]
    Supervisor.start_link(children, opts)
  end
end
