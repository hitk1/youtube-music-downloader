defmodule DataStream.DownloadMd do
  require Logger

  @output_dir "./tmp"

  def call(url) do
    yt_dlp_args = [
      "--extract-audio",
      "--audio-format", "mp3",
      "--audio-quality", "0",
      "--output", Path.join(@output_dir, "%(title)s.mp3"),
      url
    ]
    Logger.info("New Url to process: #{url}")
    case System.cmd("yt-dlp", yt_dlp_args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error_output, exit_code} -> {:error, "yt-dlp exited with code #{exit_code}: #{error_output}"}
    end
  end

end
