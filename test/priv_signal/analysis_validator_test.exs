defmodule PrivSignal.Analysis.ValidatorTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Analysis.Validator

  @diff """
  diff --git a/lib/foo.ex b/lib/foo.ex
  index 0000000..1111111 100644
  --- a/lib/foo.ex
  +++ b/lib/foo.ex
  @@ -1,2 +10,3 @@
   defmodule Foo do
  +  def bar, do: :ok
   end
  """

  test "accepts evidence within diff ranges" do
    payload = %{
      "touched_flows" => [
        %{"flow_id" => "x", "evidence" => "lib/foo.ex:10-12", "confidence" => 0.9}
      ],
      "new_pii" => [],
      "new_sinks" => [],
      "notes" => []
    }

    assert {:ok, _} = Validator.validate(payload, @diff)
  end

  test "drops evidence outside diff" do
    payload = %{
      "touched_flows" => [
        %{"flow_id" => "x", "evidence" => "lib/foo.ex:99-100", "confidence" => 0.9}
      ],
      "new_pii" => [],
      "new_sinks" => [],
      "notes" => []
    }

    assert {:ok, sanitized} = Validator.validate(payload, @diff)
    assert sanitized["touched_flows"] == []
  end
end
