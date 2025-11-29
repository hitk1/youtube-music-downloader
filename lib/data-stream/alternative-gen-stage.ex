defmodule DataStream.GenStageApproach do
  @moduledoc """
  ALTERNATIVA 2: GenStage
  =======================
  
  Para implementar isso, você precisa adicionar {:gen_stage, "~> 1.0"} ao mix.exs
  
  GenStage é ideal para pipelines de dados com backpressure explícita.
  
  Vantagens:
  - Backpressure elegante e integrada
  - Separação clara entre produtor/consumidor
  - Escalável para listas muito grandes
  - Comportamento previsível e testável
  
  Desvantagens:
  - Mais verboso
  - Curva de aprendizado maior
  - Overhead para listas pequenas
  
  Quando usar:
  ✓ Pipelines complexos (múltiplos estágios)
  ✓ Listas muito grandes
  ✓ Quando você quer backpressure explícita
  ✓ Sistemas que precisam de diferentes velocidades de processamento
  """

  # ============================================================================
  # EXEMPLO 1: Producer (lê CSV) + Consumer (baixa vídeos)
  # ============================================================================

  defmodule Producer do
    use GenStage
    require Logger

    def start_link(csv_path) do
      GenStage.start_link(__MODULE__, csv_path, name: __MODULE__)
    end

    def init(csv_path) do
      Logger.info("CSV Producer started for #{csv_path}")
      {:producer, {:file, csv_path, nil}}
    end

    def handle_demand(demand, {:file, csv_path, stream}) when demand > 0 do
      stream =
        stream ||
          (File.stream!(csv_path)
           |> Stream.map(&String.trim/1)
           |> Stream.reject(&(&1 == "")))

      {urls, stream} =
        stream
        |> Enum.take(demand)
        |> then(&{&1, Stream.drop(stream, length(&1))})

      # Se stream acabou, enviar {:halt, state}
      if Enum.empty?(urls) do
        {:stop, :normal, {:file, csv_path, stream}}
      else
        {:noreply, urls, {:file, csv_path, stream}}
      end
    end
  end

  defmodule Consumer do
    use GenStage
    require Logger
    alias DataStream.DownloadMd

    def start_link(_) do
      GenStage.start_link(__MODULE__, [], name: __MODULE__)
    end

    def init(state) do
      {:consumer, state, subscribe_to: [Producer]}
    end

    def handle_events(urls, _from, state) do
      results =
        urls
        |> Enum.map(fn url ->
          case DownloadMd.call(url) do
            {:ok, _} -> {:ok, url}
            {:error, reason} -> {:error, url, reason}
          end
        end)

      new_state = state ++ results

      if length(new_state) >= 100 do
        Logger.info("Processed 100 videos, current stats: #{inspect(new_state)}")
        {:noreply, [], []}
      else
        {:noreply, [], new_state}
      end
    end
  end

  # ============================================================================
  # EXEMPLO 2: ProducerConsumer (filtro/transformação intermediária)
  # ============================================================================

  defmodule FilterStage do
    use GenStage
    require Logger

    def start_link(_) do
      GenStage.start_link(__MODULE__, [], name: __MODULE__)
    end

    def init(state) do
      {:producer_consumer, state, subscribe_to: [Producer]}
    end

    def handle_events(urls, _from, state) do
      # Filtrar URLs válidas (exemplo: não vazias, começam com http)
      valid_urls =
        urls
        |> Enum.filter(&is_valid_url?/1)
        |> tap(fn v -> Logger.debug("Filtered: #{length(urls)} -> #{length(v)} URLs") end)

      {:noreply, valid_urls, state}
    end

    defp is_valid_url?(url) do
      String.starts_with?(url, ["http://", "https://"]) && String.length(url) > 10
    end
  end

  # ============================================================================
  # USO:
  # ============================================================================
  #
  # Adicionar ao mix.exs:
  #   {:gen_stage, "~> 1.0"}
  #
  # Adicionar ao supervisor (application.ex ou similar):
  #   children = [
  #     {DataStream.GenStageApproach.Producer, "./tmp/videos.csv"},
  #     DataStream.GenStageApproach.FilterStage,
  #     DataStream.GenStageApproach.Consumer
  #   ]
  #   Supervisor.start_link(children, strategy: :rest_for_one)
  #
  # A ordem é importante! Producer -> FilterStage -> Consumer
end
