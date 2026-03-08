defmodule Mix.Tasks.PgPushex.Push do
  use Mix.Task

  alias PgPushex.Migrator

  @shortdoc "Pushes schema state to PostgreSQL"

  @switches [repo: :string, schema: :string]
  @aliases [r: :repo, s: :schema]

  @usage """
  Usage:
    mix pg_pushex.push -r MyApp.Repo -s MyApp.Schema
    mix pg_pushex.push --repo MyApp.Repo --schema MyApp.Schema

  Fallback configuration:
    config :pg_pushex,
      repo: MyApp.Repo,
      schema: MyApp.Schema
  """

  @impl Mix.Task
  def run(args) do
    {opts, remaining_args, invalid_opts} =
      OptionParser.parse(args, strict: @switches, aliases: @aliases)

    with :ok <- validate_cli_args(remaining_args, invalid_opts),
         {:ok, repo, schema_module} <- resolve_repo_and_schema(opts) do
      Mix.Task.run("app.start")

      case Migrator.run(repo, schema_module) do
        {:ok, :pushed} ->
          Mix.shell().info([:green, "Push successful!"])

        {:ok, :no_changes} ->
          :ok

        {:error, :aborted} ->
          Mix.shell().info([:yellow, "Push aborted."])
          System.halt(0)

        {:error, reason} ->
          Mix.shell().error([:red, "Push failed: #{inspect(reason)}"])
          System.halt(1)
      end
    else
      {:error, message} ->
        print_error_and_usage(message)

      :error ->
        print_error_and_usage("Invalid command line arguments")
    end
  end

  defp validate_cli_args([], []), do: :ok

  defp validate_cli_args(remaining_args, invalid_opts) do
    details = [format_remaining_args(remaining_args), format_invalid_opts(invalid_opts)]

    message =
      details
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("; ")

    if message == "", do: :error, else: {:error, message}
  end

  defp resolve_repo_and_schema(opts) do
    repo_value = Keyword.get(opts, :repo, Application.get_env(:pg_pushex, :repo))
    schema_value = Keyword.get(opts, :schema, Application.get_env(:pg_pushex, :schema))

    with {:ok, repo} <- normalize_module(repo_value, :repo),
         {:ok, schema_module} <- normalize_module(schema_value, :schema) do
      {:ok, repo, schema_module}
    end
  end

  defp normalize_module(nil, key) do
    {:error, "Missing #{key} option. Provide --#{key} or config :pg_pushex, #{key}: ..."}
  end

  defp normalize_module(value, _key) when is_atom(value), do: {:ok, value}

  defp normalize_module(value, key) when is_binary(value) do
    module_name = String.trim(value)

    if module_name == "" do
      {:error, "#{key} module cannot be empty"}
    else
      {:ok, module_from_string(module_name)}
    end
  end

  defp normalize_module(value, key) do
    {:error, "Invalid #{key} value: #{inspect(value)}"}
  end

  defp module_from_string(module_name) do
    module_name
    |> String.trim_leading("Elixir.")
    |> String.split(".", trim: true)
    |> Module.concat()
  end

  defp format_remaining_args([]), do: ""

  defp format_remaining_args(args) do
    "Unexpected positional arguments: #{Enum.join(args, ", ")}"
  end

  defp format_invalid_opts([]), do: ""

  defp format_invalid_opts(invalid_opts) do
    rendered =
      invalid_opts
      |> Enum.map(fn
        {key, nil} -> to_string(key)
        {key, value} -> "#{key}=#{value}"
      end)
      |> Enum.join(", ")

    "Invalid options: #{rendered}"
  end

  defp print_error_and_usage(message) do
    Mix.shell().error([:red, "Error: #{message}"])
    Mix.shell().info(@usage)
    System.halt(1)
  end
end
