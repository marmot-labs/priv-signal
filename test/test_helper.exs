# Suppress logger output during tests.
Logger.configure(level: :emergency)

Path.wildcard("test/support/**/*.exs")
|> Enum.sort()
|> Enum.each(&Code.require_file/1)

ExUnit.start()
