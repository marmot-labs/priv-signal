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
        matched_nodes: [
          %{
            module: "MyApp.User",
            field: "email",
            key: "user_email",
            class: "direct_identifier",
            sensitive: true
          },
          %{
            module: "MyApp.User",
            field: "dob",
            key: "user_dob",
            class: "sensitive_context_indicator",
            sensitive: true
          }
        ],
        evidence: [
          %Evidence{
            type: :direct_field_access,
            expression: "user.email",
            fields: [
              %{module: "MyApp.User", field: "email", class: "direct_identifier", sensitive: true}
            ]
          }
        ]
      }
    ]

    [finding] = Classifier.classify(candidates)
    assert finding.classification == :confirmed_prd
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
        matched_nodes: [],
        evidence: [%Evidence{type: :bulk_inspect, expression: "inspect(params)", fields: []}]
      }
    ]

    [finding] = Classifier.classify(candidates)
    assert finding.classification == :possible_prd
    assert finding.confidence == :possible
    assert finding.sensitivity == :unknown
  end
end
