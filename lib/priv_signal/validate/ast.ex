defmodule PrivSignal.Validate.AST do
  @moduledoc false

  def parse_file(path) do
    with {:ok, source} <- read_file(path),
         {:ok, ast} <- string_to_ast(source, path) do
      {:ok, ast}
    end
  end

  def extract_modules(ast) do
    {_ast, modules} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _meta, [module_ast, [do: body]]} = node, acc ->
          case module_name(module_ast) do
            nil -> {node, acc}
            name -> {node, [%{name: name, body: body} | acc]}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(modules)
  end

  def module_forms(nil), do: []
  def module_forms({:__block__, _meta, forms}) when is_list(forms), do: forms
  def module_forms(form), do: [form]

  def extract_functions(forms) when is_list(forms) do
    forms
    |> Enum.flat_map(&extract_function/1)
  end

  def extract_calls(body_ast) do
    {_ast, acc} =
      Macro.traverse(
        body_ast,
        %{calls: [], capture_depth: 0},
        &prewalk_call/2,
        &postwalk_call/2
      )

    Enum.reverse(acc.calls)
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} -> {:ok, contents}
      {:error, reason} -> {:error, "failed to read #{path}: #{format_reason(reason)}"}
    end
  end

  defp string_to_ast(source, path) do
    case Code.string_to_quoted(source, columns: true, token_metadata: true) do
      {:ok, ast} ->
        {:ok, ast}

      {:error, {line, error, token}} ->
        {:error,
         "failed to parse #{path} at line #{format_line(line)}: #{format_parse_error(error, token)}"}
    end
  end

  defp module_name({:__aliases__, _meta, parts}) when is_list(parts) do
    parts
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join(".")
  end

  defp module_name(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> strip_elixir_prefix()
  end

  defp module_name(_), do: nil

  defp extract_function({kind, _meta, args}) when kind in [:def, :defp] do
    case extract_def_head(args) do
      {:ok, name, args_ast, body} ->
        args_ast
        |> function_arities()
        |> Enum.map(fn arity -> %{name: name, arity: arity, body: body} end)

      :error ->
        []
    end
  end

  defp extract_function(_), do: []

  defp extract_def_head([{:when, _meta, [head | _guards]}, body_kw]) do
    extract_def_head([head, body_kw])
  end

  defp extract_def_head([head, body_kw]) when is_list(body_kw) do
    with {:ok, name, args_ast} <- extract_head_name_args(head) do
      body = Keyword.get(body_kw, :do)
      {:ok, name, args_ast, body}
    end
  end

  defp extract_def_head(_), do: :error

  defp extract_head_name_args({name, _meta, args_ast}) when is_atom(name) do
    {:ok, name, args_ast || []}
  end

  defp extract_head_name_args(_), do: :error

  defp function_arities(args_ast) when is_list(args_ast) do
    total = length(args_ast)
    defaults = Enum.count(args_ast, &default_arg?/1)
    min_arity = max(total - defaults, 0)

    min_arity..total
    |> Enum.to_list()
  end

  defp default_arg?({:\\, _meta, _args}), do: true
  defp default_arg?(_), do: false

  defp prewalk_call({:&, _meta, _args} = node, acc) do
    {node, %{acc | capture_depth: acc.capture_depth + 1}}
  end

  defp prewalk_call(node, acc) do
    acc =
      if acc.capture_depth == 0 do
        maybe_add_call(node, acc)
      else
        acc
      end

    {node, acc}
  end

  defp postwalk_call({:&, _meta, _args} = node, acc) do
    {node, %{acc | capture_depth: max(acc.capture_depth - 1, 0)}}
  end

  defp postwalk_call(node, acc), do: {node, acc}

  defp maybe_add_call({{:., _meta, [module_ast, fun]}, _call_meta, args}, acc)
       when is_atom(fun) and is_list(args) do
    call = %{type: :remote, module: module_ast, name: fun, arity: length(args)}
    %{acc | calls: [call | acc.calls]}
  end

  defp maybe_add_call({fun, _meta, args}, acc) when is_atom(fun) and is_list(args) do
    call = %{type: :local, module: nil, name: fun, arity: length(args)}
    %{acc | calls: [call | acc.calls]}
  end

  defp maybe_add_call(_node, acc), do: acc

  defp strip_elixir_prefix("Elixir." <> rest), do: rest
  defp strip_elixir_prefix(other), do: other

  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)

  defp format_parse_error(error, token) do
    error_text = format_term(error)
    token_text = format_term(token)

    "#{error_text} #{token_text}" |> String.trim()
  end

  defp format_line(line) when is_integer(line), do: Integer.to_string(line)

  defp format_line(line) when is_list(line) do
    case Keyword.get(line, :line) do
      nil -> inspect(line)
      value -> to_string(value)
    end
  end

  defp format_line(other), do: format_term(other)

  defp format_term(term) when is_binary(term), do: term
  defp format_term(term) when is_atom(term), do: Atom.to_string(term)
  defp format_term(term), do: inspect(term)
end
