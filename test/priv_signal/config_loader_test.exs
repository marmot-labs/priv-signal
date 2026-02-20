defmodule PrivSignal.Config.LoaderTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Config.Loader

  test "loads config from priv-signal.yml" do
    path = Path.join(System.tmp_dir!(), "priv_signal_#{System.unique_integer([:positive])}.yml")
    File.write!(path, sample_yaml())

    assert {:ok, config} = Loader.load(path)
    assert config.version == 1
    assert length(config.prd_nodes) == 2
    assert is_struct(config.scanners, PrivSignal.Config.Scanners)
    assert config.scanners.logging.enabled
    assert config.scanners.http.enabled
    assert config.scanners.database.enabled
  end

  defp sample_yaml do
    """
    version: 1

    prd_nodes:
      - key: user_email
        label: User Email
        class: direct_identifier
        sensitive: true
        scope:
          module: MyApp.Accounts.User
          field: email
      - key: author_email
        label: Author Email
        class: direct_identifier
        sensitive: true
        scope:
          module: MyApp.Accounts.Author
          field: email

    """
  end
end
