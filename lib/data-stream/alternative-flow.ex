defmodule DataStream.FlowApproach do
  @moduledoc """
  ALTERNATIVA 3: Flow (Recomendado para uso geral)
  =================================================

  Para implementar, adicione ao mix.exs:
    {:flow, "~> 1.2"}

  Flow é built-on-top de GenStage mas com API mais simples.
  Ideal para processamento paralelo com mínimo de overhead.

  Vantagens:
  - Mais simples que GenStage
  - Distribuição de dados automática entre workers
  - Bom balanceamento de carga
  - Backpressure transparente
  - Otimizado para este tipo de problema

  Desvantagens:
  - Dependência adicional (mas vale a pena)
  - Menos controle que GenStage

  Quando usar:
  ✓ Transformações paralelas em streams
  ✓ Quando você quer "set it and forget it"
  ✓ Performance é crítica
  ✓ Listas médias a grandes
  """

  require Logger
  alias DataStream.DownloadMd

  def download_all_videos(csv_path \\ "./tmp/videos.csv") do
    Logger.info("Starting downloads with Flow approach")
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
          |> Flow.from_enumerable(max_demand: 100)
          |> Flow.map(&process_url/1)
          |> Flow.partition()  # Re-particiona para operações com side-effects
          |> Flow.reduce(fn -> {0, 0} end, fn result, {ok, err} ->
            case result do
              :ok -> {ok + 1, err}
              :error -> {ok, err + 1}
            end
          end)
          |> Enum.to_list()
          |> List.first({0, 0})

        elapsed = System.monotonic_time(:second) - start_time
        Logger.info(
          "Completed in #{elapsed}s - Success: #{elem(stats, 0)}, Failed: #{elem(stats, 1)}"
        )

        {:ok, stats}
    end
  end

  defp process_url(url) do
    case DownloadMd.call(url) do
      {:ok, _} -> :ok
      {:error, reason} ->
        Logger.error("Download failed: #{reason}")
        :error
    end
  end

  @doc """
  Exemplo mais avançado com windowing (processamento em lotes)
  """
  def download_with_batching(csv_path \\ "./tmp/videos.csv", batch_size \\ 10) do
    Logger.info("Starting downloads with batch processing (batch_size: #{batch_size})")

    csv_path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Flow.from_enumerable()
    |> Flow.chunk_every(batch_size)  # Processa em lotes
    |> Flow.map(&process_batch/1)
    |> Flow.run()
  end

  defp process_batch(urls) do
    Logger.info("Processing batch of #{length(urls)} URLs")

    urls
    |> Task.async_stream(&DownloadMd.call/1, timeout: 300_000)
    |> Enum.reduce({0, 0}, fn
      {:ok, {:ok, _}}, {ok, err} -> {ok + 1, err}
      {:ok, {:error, _}}, {ok, err} -> {ok, err + 1}
      {:error, _}, {ok, err} -> {ok, err + 1}
    end)
    |> tap(fn {ok, err} -> Logger.info("Batch results: #{ok} success, #{err} failed") end)
  end

  @doc """
  Exemplo com map_state para agregar estatísticas
  """
  def download_with_stats(csv_path \\ "./tmp/videos.csv") do
    csv_path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Flow.from_enumerable(stages: 4)  # 4 estágios paralelos
    |> Flow.map(&process_url/1)
    |> Flow.map_state(fn acc ->
      # acc contém resultados deste estágio
      [acc]
    end)
    |> Enum.to_list()
  end

  # ============================================================================
  # USO:
  # ============================================================================
  #
  # Adicionar ao mix.exs:
  #   {:flow, "~> 1.2"}
  #
  # Chamar assim:
  #   DataStream.FlowApproach.download_all_videos()
  #   DataStream.FlowApproach.download_with_batching("./tmp/videos.csv", 5)
  #
  # Para computações distribuídas entre nós:
  #   Flow.from_enumerable(enumerable, stages: System.schedulers_online())
  #
  # Opções úteis:
  #   - stages: número de paralelos (padrão: System.schedulers_online())
  #   - max_demand: máximo items pedidos por vez
  #   - min_demand: mínimo antes de pedir mais
end
