defmodule DataStream.CSVReader do
  require Logger
  
  @csv "./tmp/videos.csv"
  @timeout 30_000  # 30 segundos por vídeo

  def call() do
    case File.exists?(@csv) do
      false ->
        Logger.error("CSV file not found at #{@csv}")
        {:error, "CSV file not found"}
      
      true ->
        Logger.info("Starting video download process from #{@csv}")
        start_time = System.monotonic_time(:second)
        
        result = @csv
        |> read_and_process_urls()
        
        elapsed = System.monotonic_time(:second) - start_time
        Logger.info("Download process completed in #{elapsed} seconds")
        result
    end
  end

  defp read_and_process_urls(csv_path) do
    csv_path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Stream.with_index()
    |> Enum.reduce({0, 0}, fn {url, index}, {success, failed} ->
      Logger.info("Processing URL #{index + 1}: #{url}")
      
      case dispatch_poolboy(url) do
        :ok -> 
          {success + 1, failed}
        
        {:error, _} -> 
          {success, failed + 1}
      end
    end)
  end

  defp dispatch_poolboy(url) do
    try do
      :poolboy.transaction(
        :worker,
        fn pid -> GenServer.call(pid, {:new_link, url}, @timeout) end,
        @timeout
      )
    catch
      :exit, reason ->
        Logger.error("Worker pool transaction failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
