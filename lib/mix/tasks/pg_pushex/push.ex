defmodule Mix.Tasks.PgPushex.Push do
  @moduledoc """
  Applies the defined schema to the PostgreSQL database.

  This task compares the current database state with the desired schema
  and applies the necessary changes to bring them into sync.

  ## Usage

      mix pg_pushex.push -r MyApp.Repo -s MyApp.Schema
      mix pg_pushex.push --repo MyApp.Repo --schema MyApp.Schema

  ## Configuration

  You can also configure default values in your config:

      config :pg_pushex,
        repo: MyApp.Repo,
        schema: MyApp.Schema

  ## Interactive Features

  When the task detects potential column renames (drop + add in same table),
  it will prompt you interactively to choose whether to:

  - Rename the column (preserving data)
  - Drop and recreate (data loss)
  - Abort the operation

  ## Safety

  All changes are applied within a database transaction. If any step fails,
  the entire migration is rolled back.
  """

  use Mix.Task

  alias PgPushex.CLI.Helpers
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

    with :ok <- Helpers.validate_cli_args(remaining_args, invalid_opts),
         {:ok, repo, schema_module} <- Helpers.resolve_repo_and_schema(opts) do
      Mix.Task.run("app.start")

      case Migrator.run(repo, schema_module) do
        {:ok, :pushed} ->
          Mix.shell().info([:green, "Push successful!"])

        {:ok, :no_changes} ->
          :ok

        {:error, :aborted} ->
          Mix.shell().info([:yellow, "Push aborted."])
          System.halt(0)

        {:error, %ArgumentError{message: message}} ->
          Mix.shell().error("Schema error: #{message}")
          push_aborted_hint()
          System.halt(1)

        {:error, %Postgrex.Error{postgres: %{message: message} = pg}} ->
          code = Map.get(pg, :code, :unknown)
          Mix.shell().error("Database error (#{code}): #{message}")
          push_aborted_hint()
          System.halt(1)

        {:error, %DBConnection.ConnectionError{message: message}} ->
          Mix.shell().error("Connection error: #{message}")
          push_aborted_hint()
          System.halt(1)

        {:error, reason} ->
          Mix.shell().error("Push failed: #{inspect(reason)}")
          System.halt(1)
      end
    else
      {:error, message} ->
        Helpers.print_error_and_usage(message, @usage)

      :error ->
        Helpers.print_error_and_usage("Invalid command line arguments", @usage)
    end
  end

  defp push_aborted_hint do
    Mix.shell().error(
      "Push was aborted safely. No changes were made to your database. " <>
        "Please fix the data or schema and try again."
    )
  end
end
