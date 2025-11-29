defmodule DataStream.TaskSupervisorApproach do
  @moduledoc """
  ALTERNATIVA 1: Task.Supervisor
  ==============================
  
  Esta é uma alternativa mais simples e idiomática ao Poolboy para este caso de uso.
  
  Vantagens:
  - Código mais simples (sem GenServer boilerplate)
  - Backpressure automática (Tasks são spawned até que o sistema fique ocupado)
  - Menos dependências externas
  - Melhor performance para tarefas heterogêneas
  - Gerenciamento automático de falhas
  
  Desvantagens:
  - Menos controle fino sobre número exato de workers
  - Se houver muitas URLs, pode consumir mais memória
  
  Quando usar:
  ✓ Listas pequenas a médias (<5000 itens)
  ✓ Quando você quer simplicidade
  ✓ Tasks variam em tempo de execução
  """
  
  require Logger
  alias DataStream.DownloadMd

  def start_link(_) do
    Task.Supervisor.start_link(name: __MODULE__)
  end

  def download_all_videos(csv_path \\ "./tmp/videos.csv") do
    Logger.info("Starting downloads with Task.Supervisor approach")
    start_time = System.monotonic_time(:second)

    case File.exists?(csv_path) do
      false ->
        Logger.error("CSV not found: #{csv_path}")
        {:error, "File not found"}

      true ->
        stats =
          csv_path
          |> File.stream!()
          |> Stream.map(&String.trim/1)
          |> Stream.reject(&(&1 == ""))
          |> Task.Supervisor.async_stream(__MODULE__, :download_video, [],
            max_concurrency: 10,
            timeout: 300_000,
            on_timeout: :kill_child
          )
          |> Enum.reduce({0, 0}, fn
            {:ok, :ok}, {ok, err} -> {ok + 1, err}
            {:exit, _}, {ok, err} -> {ok, err + 1}
            {:error, _}, {ok, err} -> {ok, err + 1}
          end)

        elapsed = System.monotonic_time(:second) - start_time
        Logger.info("Completed in #{elapsed}s - Success: #{elem(stats, 0)}, Failed: #{elem(stats, 1)}")
        {:ok, stats}
    end
  end

  def download_video(url) do
    case DownloadMd.call(url) do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.error("Download failed: #{reason}")
    end
  end
end

# Adicionar ao mix.exs (children):
# {Task.Supervisor, name: DataStream.TaskSupervisorApproach}

# Usar assim:
# DataStream.TaskSupervisorApproach.download_all_videos()
