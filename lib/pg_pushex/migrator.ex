defmodule PgPushex.Migrator do
  @moduledoc """
  Orchestrates the migration process from schema definition to database state.

  This module provides the main entry point for applying schema changes to a
  PostgreSQL database. It coordinates the entire migration pipeline:

  1. **Introspection**: Reads current database structure
  2. **Diff calculation**: Compares desired vs current state
  3. **Rename resolution**: Interactively handles potential column renames
  4. **SQL generation**: Creates DDL statements for required changes
  5. **Execution**: Applies changes within a database transaction

  ## Usage

  Basic usage with defaults:

      PgPushex.Migrator.run(MyApp.Repo, MyApp.Schema)

  With custom options:

      PgPushex.Migrator.run(MyApp.Repo, MyApp.Schema,
        introspector: CustomIntrospector,
        rename_resolver: PgPushex.CLI.NonInteractive
      )

  ## Dependency Injection

  The `run/3` function accepts options to customize the migration pipeline:

  - `:introspector` - Module that implements `introspect/1` to read database state
  - `:diff` - Module that implements `compare/2` to calculate operations
  - `:sql_generator` - Module that implements `generate/1` to create SQL
  - `:rename_resolver` - Module that implements `resolve_renames/1` for interactive prompts
  - `:sql_query_fun` - Function to execute SQL (defaults to Ecto query)

  All dependencies default to the standard PostgreSQL implementations.
  """

  @typedoc """
  Function signature for executing SQL queries.

  Takes a repo module and SQL string, returns the query result.
  """
  @type sql_query_fun :: (module(), String.t() -> term())

  @typedoc """
  Options for customizing the migration pipeline.

  - `:introspector` - Module to read current database state
  - `:diff` - Module to calculate differences
  - `:sql_generator` - Module to generate SQL statements
  - `:sql_query_fun` - Custom function to execute SQL
  - `:rename_resolver` - Module to handle rename detection interactively
  """
  @type run_opt ::
          {:introspector, module()}
          | {:diff, module()}
          | {:sql_generator, module()}
          | {:sql_query_fun, sql_query_fun()}
          | {:rename_resolver, module()}

  @typedoc "List of run options."
  @type run_opts :: [run_opt()]

  @doc """
  Runs the migration with default options.

  Equivalent to `run(repo, schema_module, [])`.

  ## Parameters

  - `repo` - The Ecto repository module
  - `schema_module` - Module using `PgPushex.Schema` with defined tables

  ## Returns

  - `{:ok, :pushed}` - Changes were successfully applied
  - `{:ok, :no_changes}` - Database already matches schema
  - `{:error, reason}` - Migration failed or was aborted
  """
  @spec run(module(), module()) :: {:ok, :pushed | :no_changes} | {:error, term()}
  def run(repo, schema_module), do: run(repo, schema_module, [])

  @doc """
  Runs the migration with custom options.

  Executes the full migration pipeline within a database transaction.
  If any step fails, the entire transaction is rolled back.

  ## Parameters

  - `repo` - The Ecto repository module
  - `schema_module` - Module using `PgPushex.Schema` with defined tables
  - `opts` - Keyword list of options (see `t:run_opts/0`)

  ## Returns

  - `{:ok, :pushed}` - Changes were successfully applied
  - `{:ok, :no_changes}` - Database already matches schema
  - `{:error, :aborted}` - User aborted during rename resolution
  - `{:error, %ArgumentError{}}` - Schema validation error
  - `{:error, %Postgrex.Error{}}` - Database error during execution
  - `{:error, %DBConnection.ConnectionError{}}` - Connection error

  ## Examples

      # Basic usage
      PgPushex.Migrator.run(MyApp.Repo, MyApp.Schema)

      # With custom SQL executor for testing
      PgPushex.Migrator.run(MyApp.Repo, MyApp.Schema,
        sql_query_fun: fn _repo, sql ->
          IO.puts("Would execute: \#{sql}")
          {:ok, %Postgrex.Result{}}
        end
      )
  """
  @spec run(module(), module(), run_opts()) :: {:ok, :pushed | :no_changes} | {:error, term()}
  def run(repo, schema_module, opts) when is_list(opts) do
    try do
      deps = dependencies(opts)

      log("Calculating diff...", :cyan)

      desired_state = schema_module.__schema__()
      current_state = deps.introspector.introspect(repo)
      operations = deps.diff.compare(current_state, desired_state)

      case operations do
        [] ->
          log("No changes detected", :green)
          {:ok, :no_changes}

        _ ->
          case deps.rename_resolver.resolve_renames(operations) do
            {:ok, resolved_operations} ->
              statements = deps.sql_generator.generate(resolved_operations)
              execute_statements(repo, statements, deps.sql_query_fun)

            :abort ->
              {:error, :aborted}
          end
      end
    rescue
      e in [ArgumentError, Postgrex.Error, DBConnection.ConnectionError] ->
        {:error, e}
    end
  end

  @doc false
  defp dependencies(opts) do
    %{
      introspector: Keyword.get(opts, :introspector, PgPushex.Introspector.Postgres),
      diff: Keyword.get(opts, :diff, PgPushex.Diff),
      sql_generator: Keyword.get(opts, :sql_generator, PgPushex.SQL.Postgres),
      sql_query_fun: Keyword.get(opts, :sql_query_fun, &default_sql_query/2),
      rename_resolver: Keyword.get(opts, :rename_resolver, PgPushex.CLI.Interactive)
    }
  end

  @doc false
  defp execute_statements(repo, sql_statements, sql_query_fun) do
    case repo.transaction(fn ->
           log("Applying changes...", :cyan)

           Enum.each(sql_statements, fn sql ->
             log("Executing: #{sql}", :light_black)

             case sql_query_fun.(repo, sql) do
               {:error, exception} -> repo.rollback(exception)
               _ok -> :ok
             end
           end)
         end) do
      {:ok, _result} ->
        {:ok, :pushed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  defp default_sql_query(repo, sql) do
    Ecto.Adapters.SQL.query(repo, sql, [], log: false)
  end

  @doc false
  defp log(message, color) do
    IO.puts(IO.ANSI.format([color, message, :reset]))
  end
end
