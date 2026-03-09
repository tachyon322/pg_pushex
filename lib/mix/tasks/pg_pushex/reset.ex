defmodule Mix.Tasks.PgPushex.Reset do
  @moduledoc """
  Completely resets the database and applies the schema.

  This task will:
  1. Drop the entire database (ALL DATA WILL BE LOST)
  2. Recreate the database
  3. Push the schema to the new database

  ## DANGER

  This is a destructive operation that will **permanently delete all data**.
  You will be prompted to confirm before proceeding.

  ## Usage

      mix pg_pushex.reset -r MyApp.Repo
      mix pg_pushex.reset --repo MyApp.Repo

  ## Configuration

      config :pg_pushex,
        repo: MyApp.Repo,
        schema: MyApp.Schema

  The schema module is always taken from application config (`config :pg_pushex, schema:`).
  The `-s` flag is accepted but has no effect on this task.

  ## When to Use

  - Setting up a fresh development environment
  - Resetting test databases
  - When you want to start completely clean

  ## See Also

  - `pg_pushex.push` - Apply schema changes without data loss
  """

  use Mix.Task

  alias PgPushex.CLI.Helpers

  @shortdoc "Drops, recreates, and pushes schema to PostgreSQL"

  @switches [repo: :string, schema: :string]
  @aliases [r: :repo, s: :schema]

  @usage """
  Usage:
    mix pg_pushex.reset -r MyApp.Repo
    mix pg_pushex.reset --repo MyApp.Repo

  Schema is taken from application config:
    config :pg_pushex,
      repo: MyApp.Repo,
      schema: MyApp.Schema
  """

  @impl Mix.Task
  def run(args) do
    {opts, remaining_args, invalid_opts} =
      OptionParser.parse(args, strict: @switches, aliases: @aliases)

    with :ok <- Helpers.validate_cli_args(remaining_args, invalid_opts),
         {:ok, repo} <- Helpers.resolve_repo(opts) do
      repo_str = inspect(repo)

      Mix.shell().info("")

      unless Mix.shell().yes?(
               "Are you sure you want to reset the database for '#{repo_str}'?\n" <>
                 "This will DROP the entire database. " <>
                 IO.ANSI.red() <> "ALL DATA WILL BE LOST." <> IO.ANSI.reset()
             ) do
        Mix.shell().info("\nReset aborted.")
        System.halt(0)
      end

      Mix.shell().info("")

      repo_arg = to_string(repo)

      Mix.Task.run("ecto.drop", ["-r", repo_arg, "--force-drop"])
      Mix.Task.run("ecto.create", ["-r", repo_arg])
      Mix.Task.run("pg_pushex.push", ["-r", repo_arg])

      Mix.shell().info([:green, "Database reset successfully!"])
    else
      {:error, message} ->
        Helpers.print_error_and_usage(message, @usage)
    end
  end
end
