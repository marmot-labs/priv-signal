defmodule Fixtures.Import.Only do
  def allowed(value), do: value
  def blocked(value), do: value
end

defmodule Fixtures.Import.Caller do
  import Fixtures.Import.Only, only: [allowed: 1]

  def run(value) do
    allowed(value)
    blocked(value)
  end
end

defmodule Fixtures.Import.AmbiguousA do
  def shared(value), do: value
end

defmodule Fixtures.Import.AmbiguousB do
  def shared(value), do: value
end

defmodule Fixtures.Import.AmbiguousCaller do
  import Fixtures.Import.AmbiguousA
  import Fixtures.Import.AmbiguousB

  def run(value) do
    shared(value)
  end
end
