defmodule PrivSignal.Validate.Index do
  @moduledoc false

  alias PrivSignal.Validate.AST
  require Logger

  defstruct modules: MapSet.new(), functions: %{}

  @doc """
  Builds a deterministic symbol index of modules and functions for validation.
  """
  def build(opts \\ []) do
    start = System.monotonic_time()
    {files, errors} = source_files(opts)

    Logger.debug("[priv_signal] validate index: scanning files=#{length(files)}")

    {module_infos, parse_errors} =
      Enum.reduce(files, {[], []}, fn file, {infos, errs} ->
        case AST.parse_file(file) do
          {:ok, ast} ->
            modules =
              ast
              |> AST.extract_modules()
              |> Enum.map(fn module_info ->
                forms = AST.module_forms(module_info.body)
                Map.put(module_info, :forms, forms)
              end)

            {infos ++ modules, errs}

          {:error, reason} ->
            {infos, [reason | errs]}
        end
      end)

    errors = Enum.reverse(errors ++ parse_errors)

    result =
      if errors != [] do
        {:error, errors}
      else
        {:ok, build_index(module_infos)}
      end

    log_index_result(result)
    emit_index_telemetry(result, start, length(files))

    result
  end

  defp build_index(module_infos) do
    {modules, functions} =
      Enum.reduce(module_infos, {MapSet.new(), %{}}, fn module_info, {mods, funs} ->
        module_name = module_info.name

        functions_for_module =
          module_info.forms
          |> AST.extract_functions()
          |> Enum.map(fn %{name: name, arity: arity} -> {Atom.to_string(name), arity} end)
          |> MapSet.new()

        {
          MapSet.put(mods, module_name),
          Map.put(funs, module_name, functions_for_module)
        }
      end)

    %__MODULE__{modules: modules, functions: functions}
  end

  defp log_index_result({:ok, index}) do
    counts = index_counts(index)

    Logger.info(
      "[priv_signal] validate index built modules=#{counts.module_count} functions=#{counts.function_count}"
    )
  end

  defp log_index_result({:error, errors}) do
    Logger.error("[priv_signal] validate index failed errors=#{length(errors)}")
  end

  defp emit_index_telemetry({:ok, index}, start, file_count) do
    counts = index_counts(index)

    PrivSignal.Telemetry.emit(
      [:priv_signal, :validate, :index],
      %{duration_ms: duration_ms(start)},
      %{
        ok: true,
        file_count: file_count,
        module_count: counts.module_count,
        function_count: counts.function_count
      }
    )
  end

  defp emit_index_telemetry({:error, errors}, start, file_count) do
    PrivSignal.Telemetry.emit(
      [:priv_signal, :validate, :index],
      %{duration_ms: duration_ms(start)},
      %{ok: false, file_count: file_count, error_count: length(errors)}
    )
  end

  defp index_counts(%__MODULE__{} = index) do
    module_count = MapSet.size(index.modules)

    function_count =
      index.functions
      |> Map.values()
      |> Enum.map(&MapSet.size/1)
      |> Enum.sum()

    %{module_count: module_count, function_count: function_count}
  end

  defp duration_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :millisecond)
  end

  defp source_files(opts) do
    root = Keyword.get(opts, :root, project_root())
    paths = Keyword.get(opts, :paths, elixirc_paths())

    files =
      paths
      |> Enum.map(&Path.expand(&1, root))
      |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.ex")))
      |> Enum.uniq()
      |> Enum.sort()

    {files, []}
  end

  defp project_root do
    case Mix.Project.project_file() do
      nil -> File.cwd!()
      path -> Path.dirname(path)
    end
  end

  defp elixirc_paths do
    Mix.Project.config()
    |> Keyword.get(:elixirc_paths, ["lib"])
  end
end
