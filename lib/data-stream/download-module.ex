defmodule DataStream.DownloadMd do
  require Logger

  @output_dir "./tmp"
  @max_retries 3
  @timeout 300_000  # 5 minutos
  @backoff_base 1000  # 1 segundo

  def call(url) do
    download_with_retry(url, 0)
  end

  defp download_with_retry(url, attempt) when attempt < @max_retries do
    Logger.info("Processing URL (attempt #{attempt + 1}/#{@max_retries}): #{url}")
    
    case do_download(url) do
      {:ok, _output} = success ->
        Logger.info("✓ Successfully downloaded: #{url}")
        success
      
      {:error, reason} ->
        if attempt < @max_retries - 1 do
          backoff_time = calculate_backoff(attempt)
          Logger.warn("Download failed for #{url}: #{reason}. Retrying in #{backoff_time}ms...")
          Process.sleep(backoff_time)
          download_with_retry(url, attempt + 1)
        else
          Logger.error("✗ Failed to download #{url} after #{@max_retries} attempts: #{reason}")
          {:error, "Failed after #{@max_retries} retries: #{reason}"}
        end
    end
  end

  defp do_download(url) do
    yt_dlp_args = [
      "--extract-audio",
      "--audio-format", "mp3",
      "--audio-quality", "0",
      "--output", Path.join(@output_dir, "%(title)s.mp3"),
      url
    ]
    
    try do
      case System.cmd("yt-dlp", yt_dlp_args, stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {error_output, exit_code} -> 
          {:error, "yt-dlp exited with code #{exit_code}: #{error_output}"}
      end
    catch
      :error, reason ->
        {:error, "System error: #{inspect(reason)}"}
    end
  end

  defp calculate_backoff(attempt) do
    # Exponential backoff with jitter: base * 2^attempt + random(0-1000ms)
    backoff = @backoff_base * Integer.pow(2, attempt)
    jitter = Enum.random(0..1000)
    backoff + jitter
  end
end
