defmodule PrivSignal.Scan.InventoryTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config
  alias PrivSignal.Config.{PRDNode, PRDScope}
  alias PrivSignal.Scan.Inventory

  test "build creates normalized deterministic lookup structures" do
    config = %Config{
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

    assert Enum.map(inventory.data_nodes, & &1.field) == ["email", "email", "phone"]
  end
end
