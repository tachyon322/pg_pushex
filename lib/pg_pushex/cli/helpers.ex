defmodule PgPushex.CLI.Helpers do
  @moduledoc """
  Shared helper functions for CLI tasks.

  Provides argument parsing, module resolution, validation,
  and migration file utilities used by Mix tasks.
  """

  @doc """
  Validates command line arguments and options.

  Returns error if unexpected positional arguments or invalid options provided.

  ## Parameters

  - `remaining_args` - List of unrecognized positional arguments
  - `invalid_opts` - List of invalid options from OptionParser

  ## Returns

  - `:ok` - All arguments valid
  - `:error` - General parse error
  - `{:error, message}` - Specific error message
  """
  @spec validate_cli_args([String.t()], [{atom(), String.t() | nil}]) ::
          :ok | :error | {:error, String.t()}
  def validate_cli_args([], []), do: :ok

  def validate_cli_args(remaining_args, invalid_opts) do
    details = [format_remaining_args(remaining_args), format_invalid_opts(invalid_opts)]

    message =
      details
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("; ")

    if message == "", do: :error, else: {:error, message}
  end

  @doc """
  Resolves repo and schema module from options or config.

  ## Parameters

  - `opts` - Keyword list of CLI options

  ## Returns

  - `{:ok, repo_module, schema_module}` - Both resolved successfully
  - `{:error, message}` - Failed to resolve one or both
  """
  @spec resolve_repo_and_schema(keyword()) :: {:ok, module(), module()} | {:error, String.t()}
  def resolve_repo_and_schema(opts) do
    repo_value = Keyword.get(opts, :repo, Application.get_env(:pg_pushex, :repo))
    schema_value = Keyword.get(opts, :schema, Application.get_env(:pg_pushex, :schema))

    with {:ok, repo} <- normalize_module(repo_value, :repo),
         {:ok, schema_module} <- normalize_module(schema_value, :schema) do
      {:ok, repo, schema_module}
    end
  end

  @doc """
  Resolves just the repo module from options or config.

  ## Parameters

  - `opts` - Keyword list of CLI options

  ## Returns

  - `{:ok, repo_module}` - Resolved successfully
  - `{:error, message}` - Failed to resolve
  """
  @spec resolve_repo(keyword()) :: {:ok, module()} | {:error, String.t()}
  def resolve_repo(opts) do
    repo_value = Keyword.get(opts, :repo, Application.get_env(:pg_pushex, :repo))
    normalize_module(repo_value, :repo)
  end

  @doc """
  Normalizes a module reference to a module atom.

  Handles atoms, strings, and validates the input.

  ## Parameters

  - `value` - The module value (atom, string, or nil)
  - `key` - The option key for error messages

  ## Returns

  - `{:ok, module}` - Successfully normalized
  - `{:error, message}` - Invalid or missing value
  """
  @spec normalize_module(term(), atom()) :: {:ok, module()} | {:error, String.t()}
  def normalize_module(nil, key) do
    {:error, "Missing #{key} option. Provide --#{key} or config :pg_pushex, #{key}: ..."}
  end

  def normalize_module(value, _key) when is_atom(value), do: {:ok, value}

  def normalize_module(value, key) when is_binary(value) do
    module_name = String.trim(value)

    if module_name == "" do
      {:error, "#{key} module cannot be empty"}
    else
      {:ok, module_from_string(module_name)}
    end
  end

  def normalize_module(value, key) do
    {:error, "Invalid #{key} value: #{inspect(value)}"}
  end

  @doc """
  Converts a module name string to a module atom.

  Handles "Elixir." prefix and dot-separated names.

  ## Examples

      iex> PgPushex.CLI.Helpers.module_from_string("MyApp.Repo")
      MyApp.Repo
  """
  @spec module_from_string(String.t()) :: module()
  def module_from_string(module_name) do
    module_name
    |> String.trim_leading("Elixir.")
    |> String.split(".", trim: true)
    |> Module.concat()
  end

  @doc false
  @spec format_remaining_args([String.t()]) :: String.t()
  defp format_remaining_args([]), do: ""

  defp format_remaining_args(args) do
    "Unexpected positional arguments: #{Enum.join(args, ", ")}"
  end

  @doc false
  @spec format_invalid_opts([{atom(), String.t() | nil}]) :: String.t()
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

  @doc """
  Prints an error message and usage, then exits.

  ## Parameters

  - `message` - Error message to display
  - `usage` - Usage instructions string
  """
  @spec print_error_and_usage(String.t(), String.t()) :: no_return()
  def print_error_and_usage(message, usage) do
    Mix.shell().error([:red, "Error: #{message}"])
    Mix.shell().info(usage)
    Mix.raise(message)
  end

  @doc """
  Returns the migrations directory path for a repo.

  ## Parameters

  - `repo` - The Ecto repository module

  ## Returns

  Path string like "priv/repo/migrations"
  """
  @spec migrations_path(module()) :: String.t()
  def migrations_path(repo) do
    repo_underscore =
      repo
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    Path.join(["priv", repo_underscore, "migrations"])
  end

  @doc """
  Writes a migration file with the given code.

  Creates the migrations directory if it doesn't exist and generates
  a timestamped filename.

  ## Parameters

  - `repo` - The Ecto repository module
  - `code` - The migration code to write
  - `filename_suffix` - Suffix for the filename (e.g., "pg_pushex_push")

  ## Returns

  The full path to the created file.
  """
  @spec write_migration_file(module(), String.t(), String.t()) :: String.t()
  def write_migration_file(repo, code, filename_suffix) do
    migrations_dir = migrations_path(repo)
    File.mkdir_p!(migrations_dir)

    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M%S")
    filename = "#{timestamp}_#{filename_suffix}.exs"
    filepath = Path.join(migrations_dir, filename)

    File.write!(filepath, code)

    filepath
  end
end
