Mix.Task.run("app.start")

fixture_root = Path.expand("../test/fixtures/scan", __DIR__)
config_path = Path.join(fixture_root, "config/valid_pii.yml")

{:ok, config} = PrivSignal.Config.Loader.load(config_path)

runs = 5

durations_ms =
  Enum.map(1..runs, fn _ ->
    start = System.monotonic_time()

    {:ok, _result} =
      PrivSignal.Scan.Runner.run(config,
        source: [root: fixture_root, paths: ["lib/fixtures"]],
        max_concurrency: 2,
        timeout: 2_000
      )

    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :millisecond)
  end)

avg = Enum.sum(durations_ms) / max(length(durations_ms), 1)
p95 = Enum.sort(durations_ms) |> Enum.at(round((runs - 1) * 0.95), 0)

IO.puts("scan_perf_smoke runs=#{runs} avg_ms=#{Float.round(avg, 2)} p95_ms=#{p95}")
