defmodule PrivSignal.Scan.InventoryTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config
  alias PrivSignal.Config.{PIIEntry, PIIField}
  alias PrivSignal.Scan.Inventory

  test "build creates normalized deterministic lookup structures" do
    config = %Config{
      pii: [
        %PIIEntry{
          module: "Elixir.MyApp.Accounts.User",
          fields: [
            %PIIField{name: "Email", category: "contact", sensitivity: "medium"},
            %PIIField{name: "phone", category: "contact", sensitivity: "high"}
          ]
        },
        %PIIEntry{
          module: "MyApp.Accounts.Profile",
          fields: [%PIIField{name: "email", category: "contact", sensitivity: "medium"}]
        }
      ]
    }

    inventory = Inventory.build(config)

    assert Inventory.pii_module?(inventory, "MyApp.Accounts.User")
    assert Inventory.pii_module?(inventory, "Elixir.MyApp.Accounts.User")
    assert Inventory.key_token?(inventory, :email)
    assert Inventory.key_token?(inventory, "phone")

    email_fields = Inventory.fields_for_token(inventory, "EMAIL")
    assert length(email_fields) == 2

    assert Enum.map(inventory.fields, & &1.name) == ["email", "email", "phone"]
  end
end
