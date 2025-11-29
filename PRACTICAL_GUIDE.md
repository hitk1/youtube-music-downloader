# YouTube Downloader - Guia Prático

## 🚀 Como Usar

### Setup Inicial

```bash
# Instalar dependências
mix deps.get

# Compilar
mix compile

# Criar arquivo CSV com URLs (se não existir)
mkdir -p tmp
cat > tmp/videos.csv << 'EOF'
https://www.youtube.com/watch?v=dQw4w9WgXcQ
https://www.youtube.com/watch?v=jNQXAC9IVRw
EOF
```

### Executar Downloader (Código Atual - Poolboy Melhorado)

```elixir
# No IEx:
iex -S mix

# Executar:
iex> DataStream.CSVReader.call()

# Output esperado:
# INFO: Starting video download process from ./tmp/videos.csv
# INFO: Processing URL 1: https://www.youtube.com/watch?v=dQw4w9WgXcQ
# INFO: Processing URL (attempt 1/3): https://www.youtube.com/watch?v=dQw4w9WgXcQ
# INFO: ✓ Audio processed in 45230ms
# INFO: Download process completed in 92 seconds
```

## 📚 Explorar as Diferentes Abordagens

### 1. Ver Comparação

```elixir
iex> IO.puts(DataStream.ComparisonExamples.comparison_summary())
```

Mostra uma tabela comparativa de todas as abordagens.

### 2. Recomendação Automática

```elixir
iex> IO.puts(DataStream.ConcurrencyGuide.recommend_approach(1000))
# Recomenda Flow para ~1000 URLs
```

### 3. Ler Guia Completo

Abra `lib/data-stream/CONCURRENCY_GUIDE.ex` para uma análise detalhada.

## 🔄 Próxima Etapa: Migrar para Flow

### Passo 1: Adicionar Flow ao mix.exs

```elixir
defp deps do
  [
    {:poolboy, "~> 1.5.1"},
    {:httpoison, "~> 1.8"},
    {:flow, "~> 1.2"}  # ← Adicione esta linha
  ]
end
```

### Passo 2: Criar novo módulo com Flow

```bash
cat > lib/data-stream/flow-implementation.ex << 'EOF'
defmodule DataStream.FlowImpl do
  require Logger
  alias DataStream.DownloadMd

  def download_all_videos(csv_path \\ "./tmp/videos.csv") do
    Logger.info("Starting downloads with Flow")
    start_time = System.monotonic_time(:second)

    stats =
      csv_path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Flow.from_enumerable(stages: 5)
      |> Flow.map(&process_url/1)
      |> Flow.reduce(fn -> {0, 0} end, fn result, {ok, err} ->
        case result do
          :ok -> {ok + 1, err}
          :error -> {ok, err + 1}
        end
      end)
      |> Enum.to_list()
      |> List.first({0, 0})

    elapsed = System.monotonic_time(:second) - start_time
    Logger.info("Done! Success: #{elem(stats, 0)}, Failed: #{elem(stats, 1)}, Time: #{elapsed}s")
    {:ok, stats}
  end

  defp process_url(url) do
    case DownloadMd.call(url) do
      {:ok, _} -> :ok
      {:error, _reason} -> :error
    end
  end
end
EOF
```

### Passo 3: Usar

```elixir
mix deps.get
iex -S mix

iex> DataStream.FlowImpl.download_all_videos()
```

## 📊 Monitorar Performance

### Ver métricas de um worker

```elixir
iex> :poolboy.transaction(
  :worker,
  fn pid -> GenServer.call(pid, :stats) end,
  5000
)
# Output: %{processed: 42, failed: 2, succeeded: 40}
```

### Contar progresso do CSV

```elixir
iex> "./tmp/videos.csv"
     |> File.stream!()
     |> Stream.map(&String.trim/1)
     |> Stream.reject(&(&1 == ""))
     |> Enum.count()
# Total de URLs no arquivo
```

## ⚙️ Configuração do Pool

Se quiser ajustar o tamanho do pool, edite `lib/data-stream/poolboy.ex`:

```elixir
defp poolboy_config do
  [
    name: {:local, :worker},
    worker_module: DataStream.PoolboyWorker,
    size: 5,              # ← Aumentar se CPU tem espaço
    max_overflow: 5       # ← Aumentar para burst
  ]
end
```

**Recomendações:**
- `size`: 5-10 (yt-dlp é CPU/IO intensivo)
- `max_overflow`: igual a `size` (para flexibilidade)

## 🐛 Debugging

### Ver logs completos

```bash
# Em modo dev (default), logs estão em STDOUT
# Para melhor debugging, edite seu config/dev.exs
iex(1)> require Logger
iex(2)> Logger.configure(level: :debug)
```

### Monitorar uso de recursos

```bash
# Em outro terminal:
watch -n 1 'ps aux | grep [e]rl'
```

### Testar um único download

```elixir
iex> DataStream.DownloadMd.call("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
{:ok, "...output..."}
```

## 📝 Arquivos do Projeto

```
lib/data-stream/
├── download-module.ex          # ✅ Melhorado: retry + backoff
├── worker.ex                   # ✅ Melhorado: com métricas
├── csv-reader.ex               # ✅ Melhorado: sem redundância
├── poolboy.ex                  # ✅ Melhorado: pool realista
├── CONCURRENCY_GUIDE.ex        # 📖 Documentação de alternativas
├── COMPARISON_EXAMPLES.ex      # 📊 Exemplos comparativos
├── alternative-task-supervisor.ex  # 📘 Exemplo 1
├── alternative-gen-stage.ex        # 📘 Exemplo 2
└── alternative-flow.ex             # 📘 Exemplo 3 (RECOMENDADO)
```

## ✅ Checklist de Produção

Antes de colocar em produção, verifique:

- [ ] CSV está validado (sem linhas em branco extras)
- [ ] Diretório `./tmp` existe e é writable
- [ ] `yt-dlp` está instalado: `which yt-dlp`
- [ ] Pool size é apropriado para sua máquina
- [ ] Timeouts fazem sentido para seu use case
- [ ] Logging está configurado
- [ ] Tratamento de erro é robusto
- [ ] Graceful shutdown implementado (opcional)

## 🎓 Recursos de Aprendizado

### Elixir Concurrency
- https://hexdocs.pm/elixir/intro.html
- https://elixir-lang.org/getting-started/processes.html

### Poolboy
- https://github.com/devinus/poolboy
- https://hexdocs.pm/poolboy/

### GenStage & Flow
- https://github.com/elixir-lang/gen_stage
- https://hexdocs.pm/flow/

### yt-dlp (ferramenta de download)
- https://github.com/yt-dlp/yt-dlp

## 💬 Próximas Melhorias Sugeridas

1. **Persistência de progresso**
   - Salvar quais URLs foram processadas
   - Permitir retomar do ponto de parada

2. **Observabilidade**
   - Telemetry metrics
   - Health check endpoint (HTTP)
   - Dashboard de status

3. **Resiliência**
   - Circuit breaker se muitas falhas
   - Exponential backoff em nível de HTTP
   - DLQ (Dead Letter Queue) para URLs problemáticas

4. **Otimização**
   - Cache de downloads (não re-baixar)
   - Paralelismo em nível de arquivo (liberar espaço enquanto baixa)
   - Compressão de áudio

---

**Bom estudo! Qualquer dúvida, revise os arquivos de documentação.** 🚀
