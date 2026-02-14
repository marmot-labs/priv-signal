defmodule PrivSignal.Diff.OptionsTest do
  use ExUnit.Case, async: true

  alias PrivSignal.Diff.Options

  test "parses required base and applies defaults" do
    assert {:ok, parsed} = Options.parse(["--base", "origin/main"])

    assert parsed.base == "origin/main"
    assert parsed.candidate_ref == nil
    assert parsed.candidate_path == "priv_signal.lockfile.json"
    assert parsed.artifact_path == "priv_signal.lockfile.json"
    assert parsed.format == :human
    refute parsed.include_confidence?
    refute parsed.strict?
    assert parsed.output == nil
    refute parsed.help?
  end

  test "uses candidate-ref mode and keeps candidate path unset by default" do
    assert {:ok, parsed} =
             Options.parse([
               "--base",
               "origin/main",
               "--candidate-ref",
               "HEAD",
               "--format",
               "json"
             ])

    assert parsed.base == "origin/main"
    assert parsed.candidate_ref == "HEAD"
    assert parsed.candidate_path == nil
    assert parsed.format == :json
  end

  test "artifact-path becomes default candidate-path in workspace mode" do
    assert {:ok, parsed} =
             Options.parse([
               "--base",
               "origin/main",
               "--artifact-path",
               "artifacts/privacy/lock.json"
             ])

    assert parsed.artifact_path == "artifacts/privacy/lock.json"
    assert parsed.candidate_path == "artifacts/privacy/lock.json"
  end

  test "accepts include-confidence strict and output options" do
    assert {:ok, parsed} =
             Options.parse([
               "--base",
               "origin/main",
               "--include-confidence",
               "--strict",
               "--output",
               "tmp/diff.json"
             ])

    assert parsed.include_confidence?
    assert parsed.strict?
    assert parsed.output == "tmp/diff.json"
  end

  test "supports help without requiring base" do
    assert {:ok, %{help?: true}} = Options.parse(["--help"])
  end

  test "returns error when base is missing" do
    assert {:error, ["--base is required"]} = Options.parse([])
  end

  test "returns error for invalid format" do
    assert {:error, [error]} = Options.parse(["--base", "origin/main", "--format", "xml"])
    assert String.contains?(error, "--format must be one of: human, json")
  end

  test "returns error for mutually exclusive candidate options" do
    assert {:error, ["--candidate-ref and --candidate-path are mutually exclusive"]} =
             Options.parse([
               "--base",
               "origin/main",
               "--candidate-ref",
               "HEAD",
               "--candidate-path",
               "tmp/candidate.json"
             ])
  end

  test "returns error for unknown options" do
    assert {:error, [error]} = Options.parse(["--base", "origin/main", "--wat"])
    assert String.contains?(error, "invalid option")
  end
end
