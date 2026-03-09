defmodule PgPushex do
  @moduledoc """
  PgPushex is a schema-first database migration tool for PostgreSQL and Ecto.

  It allows you to define your database schema using a clean, declarative DSL,
  then automatically generates and applies migrations to keep your database
  in sync with the schema definition.

  ## Key Features

  - **Schema-first approach**: Define tables, columns, indexes, and foreign keys
    in a single schema file using an Elixir DSL
  - **Automatic diff calculation**: Compares desired schema with current database
    state and generates minimal required changes
  - **Interactive rename detection**: When columns are renamed, interactively
    choose whether to rename or drop/create
  - **Full migration generation**: Generate complete Ecto migrations from scratch
    without database connection
  - **Direct push to database**: Apply schema changes directly without migration files

  ## Usage

  Define your schema module:

      defmodule MyApp.Schema do
        use PgPushex.Schema

        table :users do
          column :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
          column :email, :string, size: 255, null: false
          column :is_active, :boolean, default: true

          timestamps(type: :utc_datetime)

          index :users_email_index, [:email], unique: true
        end
      end

  Push schema to database:

      mix pg_pushex.push -r MyApp.Repo -s MyApp.Schema

  Generate migration file:

      mix pg_pushex.generate -r MyApp.Repo -s MyApp.Schema

  See the README for complete documentation.
  """
end
