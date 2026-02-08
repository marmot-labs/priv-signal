defmodule PrivSignal.Infer.ModuleClassifierTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Infer.ModuleClassifier

  test "classifies by module suffix with high confidence" do
    classification =
      ModuleClassifier.classify(
        "MyAppWeb.UserController",
        "lib/my_app_web/controllers/user_controller.ex"
      )

    assert classification.kind == "controller"
    assert classification.confidence == 0.98
    assert "module_suffix:Controller" in classification.evidence_signals
  end

  test "classifies by path heuristic when suffix is unavailable" do
    classification =
      ModuleClassifier.classify("MyAppWeb.Users", "lib/my_app_web/live/users/index.ex")

    assert classification.kind == "liveview"
    assert classification.confidence == 0.85
    assert "path_contains:/live/" in classification.evidence_signals
  end

  test "returns nil for unknown modules" do
    assert ModuleClassifier.classify("MyApp.Service", "lib/my_app/service.ex") == nil
  end

  test "can filter low-confidence matches with min_confidence" do
    assert ModuleClassifier.classify("MyApp.Users", "lib/my_app_web/live/users/index.ex",
             min_confidence: 0.9
           ) == nil
  end
end
