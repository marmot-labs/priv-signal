defmodule PrivSignal.Scan.Scanner.Utils do
  @moduledoc false

  alias PrivSignal.Validate.AST

  def extract_module_functions(ast) do
    ast
    |> AST.extract_modules()
    |> Enum.map(fn module_info ->
      forms = AST.module_forms(module_info.body)

      %{
        module: module_info.name,
        forms: forms,
        functions: extract_function_defs(forms)
      }
    end)
  end

  def extract_alias_map(module_entry) when is_map(module_entry) do
    module_entry
    |> Map.get(:forms, [])
    |> Enum.reduce(%{}, fn form, acc ->
      case form do
        {:alias, _, [{:__aliases__, _, parts}]} when is_list(parts) ->
          module_name = join_alias(parts)
          short_name = parts |> List.last() |> Atom.to_string()
          Map.put(acc, short_name, module_name)

        {:alias, _, [{:__aliases__, _, parts}, [as: {:__aliases__, _, [as_part]}]]}
        when is_list(parts) and is_atom(as_part) ->
          Map.put(acc, Atom.to_string(as_part), join_alias(parts))

        _ ->
          acc
      end
    end)
  end

  def stable_sort_candidates(candidates) when is_list(candidates) do
    Enum.sort_by(candidates, &{&1.file, &1.line, &1.module, &1.function, &1.arity, &1.sink})
  end

  def meta_line(meta) when is_list(meta), do: Keyword.get(meta, :line)
  def meta_line(_), do: nil

  def module_name({:__aliases__, _, parts}) when is_list(parts) do
    parts
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join(".")
  end

  def module_name(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> case do
      "Elixir." <> rest -> rest
      other -> other
    end
  end

  def module_name(_), do: nil

  def normalize_key(value) when is_atom(value), do: Atom.to_string(value)
  def normalize_key(value) when is_binary(value), do: value
  def normalize_key(_), do: nil

  defp extract_function_defs(forms) do
    Enum.flat_map(forms, fn form ->
      case form do
        {kind, meta, args} when kind in [:def, :defp] ->
          case extract_def(args) do
            {:ok, name, arity, body} ->
              [%{name: Atom.to_string(name), arity: arity, body: body, line: meta_line(meta)}]

            :error ->
              []
          end

        _ ->
          []
      end
    end)
  end

  defp extract_def([head, body_kw]) when is_list(body_kw) do
    with {:ok, name, args_ast} <- extract_head_name_and_args(head) do
      body = Keyword.get(body_kw, :do)
      arity = length(args_ast || [])
      {:ok, name, arity, body}
    end
  end

  defp extract_def(_), do: :error

  defp extract_head_name_and_args({:when, _meta, [head | _guards]}) do
    extract_head_name_and_args(head)
  end

  defp extract_head_name_and_args({name, _meta, args_ast}) when is_atom(name) do
    {:ok, name, args_ast || []}
  end

  defp extract_head_name_and_args(_), do: :error

  defp join_alias(parts) do
    parts
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join(".")
  end
end
