defmodule PrivSignal.Scan.InventoryTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config
  alias PrivSignal.Config.{Matching, PRDNode, PRDScope}
  alias PrivSignal.Scan.Inventory

  test "build creates normalized deterministic lookup structures" do
    config = %Config{
      matching: %Matching{
        aliases: %{"invitee_email" => "email"},
        split_case: true,
        singularize: true,
        strip_prefixes: ["submitted"]
      },
      prd_nodes: [
        %PRDNode{
          key: "user_email",
          label: "User Email",
          class: "direct_identifier",
          sensitive: true,
          scope: %PRDScope{module: "Elixir.MyApp.Accounts.User", field: "Email"}
        },
        %PRDNode{
          key: "profile_email",
          label: "Profile Email",
          class: "direct_identifier",
          sensitive: false,
          scope: %PRDScope{module: "MyApp.Accounts.Profile", field: "email"}
        },
        %PRDNode{
          key: "user_phone",
          label: "User Phone",
          class: "direct_identifier",
          sensitive: true,
          scope: %PRDScope{module: "MyApp.Accounts.User", field: "phone"}
        },
        %PRDNode{
          key: "primary_email",
          label: "Primary Email",
          class: "direct_identifier",
          sensitive: true,
          scope: %PRDScope{module: "MyApp.Accounts.User", field: "primary_email"}
        }
      ]
    }

    inventory = Inventory.build(config)

    assert Inventory.prd_module?(inventory, "MyApp.Accounts.User")
    assert Inventory.prd_module?(inventory, "Elixir.MyApp.Accounts.User")
    assert Inventory.key_token?(inventory, :email)
    assert Inventory.key_token?(inventory, "phone")

    email_nodes = Inventory.nodes_for_token(inventory, "EMAIL")
    assert length(email_nodes) == 2
    assert length(Inventory.nodes_for_token(inventory, "submitted_emails")) == 2
    assert length(Inventory.nodes_for_token(inventory, "userEmail")) == 2
    assert length(Inventory.nodes_for_token(inventory, "invitee_email")) == 2
    assert length(Inventory.nodes_for_token(inventory, "submitted_primary_emails")) == 1
    assert Inventory.nodes_for_token(inventory, "actor_user_id") == []

    invitee_matches = Inventory.matches_for_token(inventory, "invitee_email")
    assert Enum.all?(invitee_matches, &(&1.source == :alias))

    assert Enum.map(inventory.data_nodes, & &1.field) == ["primary_email", "email", "email", "phone"]
  end

  test "strict_exact_only bypasses alias and normalized matching" do
    inventory =
      Inventory.build(%Config{
        strict_exact_only: true,
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

    assert length(Inventory.nodes_for_token(inventory, "email")) == 1
    assert Inventory.nodes_for_token(inventory, "invitee_email") == []
    assert Inventory.nodes_for_token(inventory, "submitted_emails") == []
  end
end
