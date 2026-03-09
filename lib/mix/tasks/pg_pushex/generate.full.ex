defmodule Mix.Tasks.PgPushex.Generate.Full do
  @moduledoc """
  Generates a complete Ecto migration from the schema DSL.

  Unlike `pg_pushex.generate`, this task does not require a database
  connection. It generates a full migration that creates all tables,
  columns, indexes, and constraints defined in your schema.

  ## Usage

      mix pg_pushex.generate.full -r MyApp.Repo -s MyApp.Schema
      mix pg_pushex.generate.full --repo MyApp.Repo --schema MyApp.Schema

  ## When to Use

  Use this task when:
  - Setting up a new project
  - Creating the initial migration
  - You want a complete, self-contained migration file

  The generated migration assumes an empty database and creates
  everything from scratch.

  ## Output

  Creates a migration file in `priv/repo/migrations/` with a timestamp
  and the suffix `_pg_pushex_full.exs`.
  """

  use Mix.Task

  alias PgPushex.{Diff, MigrationGenerator}
  alias PgPushex.CLI.Helpers
  alias PgPushex.State.Schema

  @shortdoc "Generates a full Ecto migration from DSL schema (no DB connection needed)"

  @switches [repo: :string, schema: :string]
  @aliases [r: :repo, s: :schema]

  @usage """
  Usage:
    mix pg_pushex.generate.full -r MyApp.Repo -s MyApp.Schema
    mix pg_pushex.generate.full --repo MyApp.Repo --schema MyApp.Schema

  Fallback configuration:
    config :pg_pushex,
      repo: MyApp.Repo,
      schema: MyApp.Schema
  """

  @impl Mix.Task
  def run(args) do
    {opts, remaining_args, invalid_opts} =
      OptionParser.parse(args, strict: @switches, aliases: @aliases)

    with :ok <- Helpers.validate_cli_args(remaining_args, invalid_opts),
         {:ok, repo, schema_module} <- Helpers.resolve_repo_and_schema(opts) do
      Mix.Task.run("loadpaths")
      Mix.Task.run("compile")

      desired_state = schema_module.__schema__()
      empty_state = %Schema{tables: %{}}
      operations = Diff.compare(empty_state, desired_state)

      case operations do
        [] ->
          Mix.shell().info([:green, "Schema is empty. Nothing to generate."])

        _ ->
          migration_code = MigrationGenerator.generate(repo, operations, suffix: "PgPushexFull")
          filepath = Helpers.write_migration_file(repo, migration_code, "pg_pushex_full")
          Mix.shell().info([:green, "Full migration generated: #{filepath}"])
      end
    else
      {:error, message} ->
        Helpers.print_error_and_usage(message, @usage)
    end
  end
end
