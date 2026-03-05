defmodule PrivSignal.Scan.Scanner.EvidenceTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config
  alias PrivSignal.Config.{Matching, PRDNode, PRDScope}
  alias PrivSignal.Scan.Inventory
  alias PrivSignal.Scan.Scanner.Evidence

  test "collect tags exact, normalized, and alias token matches" do
    inventory =
      Inventory.build(%Config{
        matching: %Matching{
          aliases: %{"invitee_email" => "email"},
          singularize: true,
          split_case: true,
          strip_prefixes: ["submitted"]
        },
        prd_nodes: [
          %PRDNode{
            key: "user_email",
            label: "User Email",
            class: "direct_identifier",
            sensitive: true,
            scope: %PRDScope{module: "MyApp.User", field: "email"}
          }
        ]
      })

    exact = Evidence.collect(quote(do: %{email: user.email}), inventory)
    normalized = Evidence.collect(quote(do: %{submitted_emails: user.emails}), inventory)
    aliased = Evidence.collect(quote(do: %{invitee_email: user.invitee_email}), inventory)

    assert Enum.any?(exact, &(&1.match_source == :exact))
    assert Enum.any?(normalized, &(&1.match_source == :normalized))
    assert Enum.any?(aliased, &(&1.match_source == :alias))
  end
end
