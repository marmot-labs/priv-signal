defmodule PrivSignal.Scan.ClassifierTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Scan.Classifier
  alias PrivSignal.Scan.Evidence

  test "classifies direct evidence as confirmed with highest sensitivity" do
    candidates = [
      %{
        module: "MyApp.Log",
        function: "emit",
        arity: 1,
        file: "lib/my_app/log.ex",
        line: 12,
        sink: "Logger.info",
        matched_fields: [
          %{module: "MyApp.User", name: "email", category: "contact", sensitivity: "medium"},
          %{module: "MyApp.User", name: "dob", category: "special", sensitivity: "high"}
        ],
        evidence: [
          %Evidence{
            type: :direct_field_access,
            expression: "user.email",
            fields: [%{module: "MyApp.User", name: "email", sensitivity: "medium"}]
          }
        ]
      }
    ]

    [finding] = Classifier.classify(candidates)
    assert finding.classification == :confirmed_pii
    assert finding.confidence == :confirmed
    assert finding.sensitivity == :high
    assert byte_size(finding.id) == 16
  end

  test "classifies bulk inspect evidence as possible" do
    candidates = [
      %{
        module: "MyApp.Log",
        function: "emit",
        arity: 1,
        file: "lib/my_app/log.ex",
        line: 24,
        sink: "Logger.debug",
        matched_fields: [],
        evidence: [%Evidence{type: :bulk_inspect, expression: "inspect(params)", fields: []}]
      }
    ]

    [finding] = Classifier.classify(candidates)
    assert finding.classification == :possible_pii
    assert finding.confidence == :possible
    assert finding.sensitivity == :unknown
  end
end
