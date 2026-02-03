defmodule PrivSignal.Diff.HunksTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Diff.Hunks

  test "parses ranges per file" do
    diff = """
    diff --git a/lib/foo.ex b/lib/foo.ex
    index 0000000..1111111 100644
    --- a/lib/foo.ex
    +++ b/lib/foo.ex
    @@ -1,2 +10,3 @@
     defmodule Foo do
    +  def bar, do: :ok
     end
    """

    ranges = Hunks.ranges_by_file(diff)

    assert [{10, 12}] = Map.get(ranges, "lib/foo.ex")
  end
end
