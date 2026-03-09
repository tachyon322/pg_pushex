defmodule PgPushex.Integration.TestCase do
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL
  alias PgPushex.State.{Column, Schema, Table, Index, ForeignKey}
  alias PgPushex.Diff
  alias PgPushex.SQL.Postgres, as: SQLGenerator

  using do
    quote do
      alias PgPushex.TestRepo
      alias PgPushex.Introspector.Postgres
      alias PgPushex.Diff
      alias PgPushex.SQL.Postgres, as: SQLGenerator
      alias PgPushex.State.{Column, Schema, Table, Index, ForeignKey}

      import PgPushex.Integration.TestCase
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(PgPushex.TestRepo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(PgPushex.TestRepo, {:shared, self()})
    end

    on_exit(fn ->
      reset_database()
    end)

    :ok
  end

  def reset_database do
    SQL.query!(PgPushex.TestRepo, "DROP SCHEMA public CASCADE;", [])
    SQL.query!(PgPushex.TestRepo, "CREATE SCHEMA public;", [])
    SQL.query!(PgPushex.TestRepo, "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";", [])
    SQL.query!(PgPushex.TestRepo, "CREATE EXTENSION IF NOT EXISTS vector;", [])
  end

  def execute_sql(sql) when is_binary(sql) do
    SQL.query!(PgPushex.TestRepo, sql, [])
  end

  def execute_sql(sqls) when is_list(sqls) do
    Enum.each(sqls, &execute_sql/1)
  end

  def create_table_sql(name, columns, opts \\ []) do
    columns_sql =
      columns
      |> Enum.map(fn
        {name, type} -> "#{name} #{type}"
        {name, type, constraints} -> "#{name} #{type} #{constraints}"
      end)
      |> Enum.join(", ")

    sql = "CREATE TABLE #{name} (#{columns_sql})"

    sql =
      case Keyword.get(opts, :primary_key) do
        nil -> sql
        pk -> "#{sql}, PRIMARY KEY (#{pk})"
      end

    sql <> ";"
  end

  def introspect_schema do
    PgPushex.Introspector.Postgres.introspect(PgPushex.TestRepo)
  end

  def build_column(name, type, opts \\ []) do
    is_pk = Keyword.get(opts, :primary_key, false)
    null_value = if is_pk, do: false, else: Keyword.get(opts, :null, true)

    %Column{
      name: name,
      type: type,
      null: null_value,
      default: Keyword.get(opts, :default),
      primary_key: is_pk,
      references: Keyword.get(opts, :references),
      enum: Keyword.get(opts, :enum),
      size: Keyword.get(opts, :size),
      generated_as: Keyword.get(opts, :generated_as),
      on_delete: Keyword.get(opts, :on_delete, :nothing),
      on_update: Keyword.get(opts, :on_update, :nothing)
    }
  end

  def build_table(name, columns, opts \\ []) do
    indexes = Keyword.get(opts, :indexes, [])
    foreign_keys = Keyword.get(opts, :foreign_keys, [])

    %Table{
      name: name,
      columns: columns,
      indexes: indexes,
      foreign_keys: foreign_keys
    }
  end

  def build_schema(tables) when is_list(tables) do
    %Schema{tables: Map.new(tables, &{&1.name, &1})}
  end

  def push_schema!(desired_schema) do
    current = introspect_schema()
    operations = Diff.compare(current, desired_schema)
    sql_statements = SQLGenerator.generate(operations)

    Enum.each(sql_statements, fn sql ->
      execute_sql(sql)
    end)

    :ok
  end
end
