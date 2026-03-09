defmodule Mix.Tasks.PgPushex.Generate do
  @moduledoc """
  Generates an Ecto migration from the current database state.

  Compares the current database with the desired schema and generates
  an Ecto migration file containing only the necessary changes.

  ## Usage

      mix pg_pushex.generate -r MyApp.Repo -s MyApp.Schema
      mix pg_pushex.generate --repo MyApp.Repo --schema MyApp.Schema

  ## Output

  Creates a migration file in `priv/repo/migrations/` with a timestamp
  and the suffix `_pg_pushex_push.exs`.

  ## Interactive Features

  When potential column renames are detected, you will be prompted to
  resolve them before the migration is generated.

  ## Configuration

      config :pg_pushex,
        repo: MyApp.Repo,
        schema: MyApp.Schema
  """

  use Mix.Task

  alias PgPushex.{Diff, MigrationGenerator}
  alias PgPushex.CLI.Helpers
  alias PgPushex.CLI.Interactive

  @shortdoc "Generates an Ecto migration from schema diff"

  @switches [repo: :string, schema: :string]
  @aliases [r: :repo, s: :schema]

  @usage """
  Usage:
    mix pg_pushex.generate -r MyApp.Repo -s MyApp.Schema
    mix pg_pushex.generate --repo MyApp.Repo --schema MyApp.Schema

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
      Mix.Task.run("app.start")

      desired_state = schema_module.__schema__()
      current_state = PgPushex.Introspector.Postgres.introspect(repo)
      operations = Diff.compare(current_state, desired_state)

      case operations do
        [] ->
          Mix.shell().info([
            :green,
            "No changes between db and schema detected. Nothing to generate."
          ])

        _ ->
          case Interactive.resolve_renames(operations) do
            {:ok, resolved_operations} ->
              migration_code =
                MigrationGenerator.generate(repo, resolved_operations, suffix: "PgPushexPush")

              filepath = Helpers.write_migration_file(repo, migration_code, "pg_pushex_push")
              Mix.shell().info([:green, "Migration generated: #{filepath}"])

            :abort ->
              Mix.shell().info([:yellow, "Generation aborted."])
              System.halt(0)
          end
      end
    else
      {:error, message} ->
        Helpers.print_error_and_usage(message, @usage)
    end
  end
end
