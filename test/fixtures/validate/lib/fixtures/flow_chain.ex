defmodule Fixtures.Flow.Start do
  def run(value) do
    Fixtures.Flow.Middle.handle(value)
  end
end

defmodule Fixtures.Flow.Middle do
  def handle(value) do
    Fixtures.Flow.End.finish(value)
  end
end

defmodule Fixtures.Flow.End do
  def finish(value), do: value
end
