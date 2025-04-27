defmodule DataStream.CSVReader do
  @csv "./tmp/videos.csv"

  def call() do
    @csv
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Task.async_stream(&dispatch_poolboy/1, timeout: :infinity)
    |> Stream.run()
  end

  defp dispatch_poolboy(url) do
    :poolboy.transaction(
          :worker,
          fn pid -> GenServer.call(pid, {:new_link, url}, :infinity) end,
          :infinity
        )
  end
end
