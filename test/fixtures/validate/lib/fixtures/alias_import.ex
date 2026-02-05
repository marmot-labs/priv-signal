defmodule Fixtures.Alias.Target do
  def call(value), do: value
end

defmodule Fixtures.Alias.Caller do
  alias Fixtures.Alias.Target

  def run(value) do
    Target.call(value)
  end
end
