defmodule DataStream.ComparisonExamples do
  @moduledoc """
  EXEMPLOS PRÁTICOS DE IMPLEMENTAÇÃO
  ==================================

  Este módulo mostra lado-a-lado como implementar a mesma funcionalidade
  com cada abordagem de concorrência.

  Problema a resolver:
  - Ler CSV com URLs de vídeos
  - Baixar cada vídeo em paralelo
  - Reportar progresso
  - Falhar gracefully
  """

  require Logger

  # ===========================================================================
  # ABORDAGEM 1: SEQUENCIAL (❌ LENTO - Baseline)
  # ===========================================================================

  defmodule Sequential do
    @moduledoc "Processamento sequencial - muito lento"

    def download_all(csv_path) do
      start = System.monotonic_time(:second)

      results =
        csv_path
        |> File.stream!()
        |> Stream.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(&DataStream.DownloadMd.call/1)

      elapsed = System.monotonic_time(:second) - start
      {results, elapsed}
    end

    # Tempo estimado para 100 vídeos (60s cada):
    # 100 * 60 = 6000 segundos (~1.67 horas)
    #
    # ❌ NUNCA use assim em produção!
  end

  # ===========================================================================
  # ABORDAGEM 2: Task.Supervisor (✅ SIMPLES & BOM)
  # ===========================================================================

  defmodule TaskSupervisor do
    @moduledoc """
    Vantagens:
    - Código simples
    - Sem pool fixo (scale automático)
    - Backpressure por padrão

    Desvantagens:
    - Menos controle fino
    - Mais memória se muitos itens
    """

    def download_all(csv_path) do
      start = System.monotonic_time(:second)

      results =
        csv_path
        |> File.stream!()
        |> Stream.map(&String.trim/1)
        |> Stream.reject(&(&1 == ""))
        |> Task.async_stream(&DataStream.DownloadMd.call/1,
          max_concurrency: 10,
          timeout: 300_000
        )
        |> Enum.to_list()

      elapsed = System.monotonic_time(:second) - start
      {results, elapsed}
    end

    # Tempo estimado: 100 * 60 / 10 = 600 segundos (~10 minutos)
    # ✅ 36x mais rápido que sequencial!
  end

  # ===========================================================================
  # ABORDAGEM 3: Poolboy (✅ CONTROLE FINO)
  # ===========================================================================

  defmodule Poolboy do
    @moduledoc """
    Abordagem atual, melhorada. Vantagens:
    - Controle fino sobre pool
    - Perfeito para long-running workers
    - Bom para stateful workers

    Desvantagens:
    - Mais código boilerplate
    - Menos automático
    """

    def download_all(csv_path) do
      start = System.monotonic_time(:second)

      {ok, err} =
        csv_path
        |> File.stream!()
        |> Stream.map(&String.trim/1)
        |> Stream.reject(&(&1 == ""))
        |> Enum.reduce({0, 0}, fn url, {ok, err} ->
          case dispatch(url) do
            :ok -> {ok + 1, err}
            :error -> {ok, err + 1}
          end
        end)

      elapsed = System.monotonic_time(:second) - start
      {{:ok, ok, :error, err}, elapsed}
    end

    defp dispatch(url) do
      try do
        :poolboy.transaction(
          :worker,
          fn pid -> GenServer.call(pid, {:new_link, url}, 30_000) end,
          30_000
        )
      catch
        :exit, _reason -> :error
      end
    end

    # Tempo estimado: Similar ao Task.Supervisor, depende da config do pool
  end

  # ===========================================================================
  # ABORDAGEM 4: Flow (⭐ RECOMENDADO)
  # ===========================================================================

  defmodule Flow do
    @moduledoc """
    Flow é GenStage simplificado. Vantagens:
    - Simples como Task.async_stream
    - Performático como Poolboy
    - Escalável como GenStage
    - Built-in backpressure

    Desvantagens:
    - Uma dependência extra (mas vale MUITO a pena)
    """

    def download_all(csv_path) do
      start = System.monotonic_time(:second)

      {ok, err} =
        csv_path
        |> File.stream!()
        |> Stream.map(&String.trim/1)
        |> Stream.reject(&(&1 == ""))
        |> Flow.from_enumerable(stages: 4)  # 4 paralelos automáticos
        |> Flow.map(&process_with_stats/1)
        |> Flow.reduce(fn -> {0, 0} end, fn result, {ok, err} ->
          case result do
            :ok -> {ok + 1, err}
            :error -> {ok, err + 1}
          end
        end)
        |> Enum.to_list()
        |> List.first({0, 0})

      elapsed = System.monotonic_time(:second) - start
      {{:ok, ok, :error, err}, elapsed}
    end

    defp process_with_stats(url) do
      case DataStream.DownloadMd.call(url) do
        {:ok, _} -> :ok
        {:error, _reason} -> :error
      end
    end

    # Tempo estimado: Melhor que Task.Supervisor em listas grandes
  end

  # ===========================================================================
  # ABORDAGEM 5: GenStage (✅ PARA PIPELINES COMPLEXOS)
  # ===========================================================================

  defmodule GenStageApproach do
    @moduledoc """
    Quando a coisa fica complexa (múltiplos estágios de processamento).
    
    Neste exemplo: CSV → Validação → Download → Agregar stats

    Vantagens:
    - Pipeline elegante e composável
    - Cada estágio é independente
    - Fácil de testar cada parte
    - Backpressure explícita

    Desvantagens:
    - Mais verboso
    - Curva de aprendizado
    - Overkill para casos simples
    """

    # Producer: lê CSV
    defmodule Producer do
      use GenStage

      def start_link(csv_path) do
        GenStage.start_link(__MODULE__, csv_path, name: __MODULE__)
      end

      def init(csv_path) do
        {:producer, {csv_path, nil}}
      end

      def handle_demand(demand, {csv_path, stream}) when demand > 0 do
        stream = stream || File.stream!(csv_path)

        {urls, new_stream} =
          stream
          |> Stream.map(&String.trim/1)
          |> Stream.reject(&(&1 == ""))
          |> Enum.split(demand)

        if Enum.empty?(urls) do
          {:stop, :normal, {csv_path, new_stream}}
        else
          {:noreply, urls, {csv_path, new_stream}}
        end
      end
    end

    # ProducerConsumer: Valida URLs
    defmodule Validator do
      use GenStage

      def start_link(_) do
        GenStage.start_link(__MODULE__, [], name: __MODULE__)
      end

      def init(state) do
        {:producer_consumer, state, subscribe_to: [Producer]}
      end

      def handle_events(urls, _from, state) do
        valid =
          urls
          |> Enum.filter(fn url ->
            String.starts_with?(url, ["http://", "https://"])
          end)

        {:noreply, valid, state}
      end
    end

    # Consumer: Download + Stats
    defmodule Downloader do
      use GenStage
      require Logger

      def start_link(_) do
        GenStage.start_link(__MODULE__, {0, 0}, name: __MODULE__)
      end

      def init(state) do
        {:consumer, state, subscribe_to: [Validator]}
      end

      def handle_events(urls, _from, {ok, err}) do
        {new_ok, new_err} =
          urls
          |> Enum.reduce({ok, err}, fn url, {acc_ok, acc_err} ->
            case DataStream.DownloadMd.call(url) do
              {:ok, _} -> {acc_ok + 1, acc_err}
              {:error, _} -> {acc_ok, acc_err + 1}
            end
          end)

        Logger.info("Stats: OK=#{new_ok}, ERR=#{new_err}")
        {:noreply, [], {new_ok, new_err}}
      end
    end

    # Uso:
    # children = [Producer, Validator, Downloader]
    # Supervisor.start_link(children, strategy: :rest_for_one)
  end

  # ===========================================================================
  # COMPARAÇÃO DE CÓDIGO
  # ===========================================================================

  @doc """
  Resumo comparativo: Linhas de código necessárias
  """
  def comparison_summary do
    """
    ┌──────────────────┬────────┬──────────┬────────────┐
    │ Abordagem        │ Código │ Performance│ Flexibilidade │
    ├──────────────────┼────────┼──────────┼────────────┤
    │ Sequencial       │   5    │    ⭐     │     ⭐      │
    │ Task.Supervisor  │  15    │   ⭐⭐⭐   │    ⭐⭐⭐    │
    │ Poolboy          │  40    │   ⭐⭐⭐⭐  │     ⭐⭐⭐    │
    │ Flow             │  20    │   ⭐⭐⭐⭐⭐ │    ⭐⭐⭐⭐   │
    │ GenStage         │  80    │   ⭐⭐⭐⭐⭐ │     ⭐⭐⭐⭐⭐ │
    └──────────────────┴────────┴──────────┴────────────┘

    Tempo para 100 vídeos (60s cada):
    Sequencial:       6000s (~100 min)      ❌
    Task.Supervisor:   600s (~10 min)      ✅
    Poolboy:           600s (~10 min)      ✅
    Flow:              550s (~9 min)       ✅✅
    GenStage:          550s (~9 min)       ✅✅

    RECOMENDAÇÃO:
    - Começar: Task.Supervisor
    - Produção: Flow
    - Pipelines complexos: GenStage
    """
  end
end
