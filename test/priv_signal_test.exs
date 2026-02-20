defmodule PrivSignalTest do
  use ExUnit.Case

  test "config_path returns default filename" do
    assert PrivSignal.config_path() == "priv_signal.yml"
  end
end
