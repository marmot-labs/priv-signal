defmodule PrivSignal.Validate.ASTTest do
  use ExUnit.Case

  alias PrivSignal.Validate.AST

  test "parse_file returns ok for valid source" do
    tmp_dir = Path.join(System.tmp_dir!(), "validate_ast_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    path = Path.join(tmp_dir, "sample.ex")
    File.write!(path, "defmodule Foo do end")

    assert {:ok, _ast} = AST.parse_file(path)
  end

  test "parse_file returns error for invalid source" do
    tmp_dir = Path.join(System.tmp_dir!(), "validate_ast_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    path = Path.join(tmp_dir, "bad.ex")
    File.write!(path, "defmodule Foo do")

    assert {:error, reason} = AST.parse_file(path)
    assert String.contains?(reason, "failed to parse")
  end

  test "extract_modules returns full module name" do
    {:ok, ast} = Code.string_to_quoted("defmodule Foo.Bar.Baz do end")

    assert [%{name: "Foo.Bar.Baz"}] = AST.extract_modules(ast)
  end

  test "extract_functions captures arities for defaults and guards" do
    source = """
    defmodule Foo do
      def foo(a, b \\\\ 1) when is_integer(a), do: a + b
      defp bar(x), do: x
    end
    """

    {:ok, ast} = Code.string_to_quoted(source)
    [%{body: body}] = AST.extract_modules(ast)

    functions =
      body
      |> AST.module_forms()
      |> AST.extract_functions()

    assert Enum.any?(functions, &(&1.name == :foo and &1.arity == 1))
    assert Enum.any?(functions, &(&1.name == :foo and &1.arity == 2))
    assert Enum.any?(functions, &(&1.name == :bar and &1.arity == 1))
  end

  test "extract_calls captures remote and local calls" do
    source = """
    defmodule Foo do
      def run(x) do
        Bar.baz(x)
        local(x)
      end

      def local(x), do: x
    end
    """

    {:ok, ast} = Code.string_to_quoted(source)
    [%{body: body}] = AST.extract_modules(ast)

    functions =
      body
      |> AST.module_forms()
      |> AST.extract_functions()

    run = Enum.find(functions, &(&1.name == :run))
    calls = AST.extract_calls(run.body)

    assert Enum.any?(calls, fn call ->
             call.type == :remote and match?({:__aliases__, _, [:Bar]}, call.module) and
               call.name == :baz and
               call.arity == 1
           end)

    assert Enum.any?(calls, fn call ->
             call.type == :local and call.name == :local and call.arity == 1
           end)
  end
end
