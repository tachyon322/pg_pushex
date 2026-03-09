defmodule PgPushex.SQL.Postgres do
  @moduledoc """
  Generates PostgreSQL DDL statements from diff operations.

  This module converts the operations produced by `PgPushex.Diff` into
  raw PostgreSQL SQL statements. It handles:

  - Creating and dropping tables with proper constraints
  - Column modifications (add, drop, alter, rename)
  - Index creation and removal
  - Foreign key constraints
  - PostgreSQL extensions
  - Custom ENUM types
  - Generated columns
  - Raw SQL execution

  Generated SQL follows PostgreSQL best practices and uses proper
  identifier quoting to prevent SQL injection.
  """

  alias PgPushex.State.{Column, ForeignKey, Table}

  @typedoc """
  An operation that can be converted to PostgreSQL SQL.

  See `PgPushex.Diff.operation/0` for the full list of supported operations.
  """
  @type operation ::
          {:create_extension, String.t()}
          | {:create_table, Table.name(), Table.t()}
          | {:drop_table, Table.name()}
          | {:add_column, Table.name(), Column.t()}
          | {:drop_column, Table.name(), Column.name()}
          | {:rename_column, Table.name(), Column.name(), Column.name()}
          | {:alter_column, Table.name(), Column.name(), keyword()}
          | {:create_index, Table.name(), PgPushex.State.Index.t()}
          | {:drop_index, Table.name(), atom() | String.t()}
          | {:create_type_enum, String.t(), [String.t()]}
          | {:execute_sql, String.t()}

  @doc """
  Generates SQL statements from a list of diff operations.

  Each operation is converted to one or more PostgreSQL DDL statements.
  The statements are returned as a list of strings, ready to be executed
  in order.

  ## Parameters

  - `operations` - List of operations from `PgPushex.Diff.compare/2`

  ## Returns

  List of SQL statement strings.

  ## Examples

      operations = [
        {:create_table, :users, %Table{columns: [...]}},
        {:create_index, :users, %Index{name: :email_idx, ...}}
      ]
      statements = PgPushex.SQL.Postgres.generate(operations)
      # Returns: ["CREATE TABLE ...", "CREATE INDEX ..."]
  """
  @spec generate([operation()]) :: [String.t()]
  def generate(operations) when is_list(operations) do
    Enum.flat_map(operations, &operation_to_sql/1)
  end

  defp operation_to_sql({:create_extension, extension_name}) when is_binary(extension_name) do
    escaped = String.replace(extension_name, "\"", "\"\"")
    ["CREATE EXTENSION IF NOT EXISTS \"#{escaped}\";"]
  end

  defp operation_to_sql({:create_table, table_name, %Table{} = table}) do
    pk_columns = Enum.filter(table.columns, & &1.primary_key)

    columns_sql =
      table.columns
      |> Enum.map(&column_definition(&1, table, :skip_pk))
      |> Enum.join(", ")

    pk_fragment =
      case pk_columns do
        [] ->
          ""

        cols ->
          pk_cols = cols |> Enum.map(&quote_ident(&1.name)) |> Enum.join(", ")
          ", PRIMARY KEY (#{pk_cols})"
      end

    ["CREATE TABLE #{quote_ident(table_name)} (#{columns_sql}#{pk_fragment});"]
  end

  defp operation_to_sql({:drop_table, table_name}) do
    ["DROP TABLE #{quote_ident(table_name)};"]
  end

  defp operation_to_sql({:add_column, table_name, %Column{} = column}) do
    fks =
      if column.references do
        [
          %ForeignKey{
            column_name: column.name,
            referenced_table: column.references,
            referenced_column: :id,
            on_delete: column.on_delete,
            on_update: column.on_update
          }
        ]
      else
        []
      end

    table = %Table{name: table_name, columns: [column], foreign_keys: fks, indexes: []}

    [
      "ALTER TABLE #{quote_ident(table_name)} ADD COLUMN #{column_definition(column, table, :inline_pk)};"
    ]
  end

  defp operation_to_sql({:drop_column, table_name, column_name}) do
    ["ALTER TABLE #{quote_ident(table_name)} DROP COLUMN #{quote_ident(column_name)};"]
  end

  defp operation_to_sql({:rename_column, table_name, old_name, new_name}) do
    [
      "ALTER TABLE #{quote_ident(table_name)} RENAME COLUMN #{quote_ident(old_name)} TO #{quote_ident(new_name)};"
    ]
  end

  defp operation_to_sql({:alter_column, table_name, column_name, changes})
       when is_list(changes) do
    Enum.map(changes, &alter_column_change_sql(table_name, column_name, &1))
  end

  defp operation_to_sql({:create_type_enum, enum_name, values}) do
    values_sql = Enum.map(values, &render_default/1) |> Enum.join(", ")
    quoted_name = quote_ident(enum_name)

    [
      "DO $$ BEGIN CREATE TYPE #{quoted_name} AS ENUM (#{values_sql}); EXCEPTION WHEN duplicate_object THEN null; END $$;"
    ]
  end

  defp operation_to_sql({:alter_enum, enum_name, added_values}) do
    Enum.map(added_values, fn value ->
      "ALTER TYPE #{quote_ident(enum_name)} ADD VALUE IF NOT EXISTS '#{value}';"
    end)
  end

  defp operation_to_sql({:create_index, table_name, %PgPushex.State.Index{} = index}) do
    unique_fragment = if index.unique, do: "UNIQUE ", else: ""
    columns_sql = Enum.map(index.columns, &quote_ident/1) |> Enum.join(", ")

    [
      "CREATE #{unique_fragment}INDEX #{quote_ident(index.name)} ON #{quote_ident(table_name)} (#{columns_sql});"
    ]
  end

  defp operation_to_sql({:drop_index, _table_name, index_name}) do
    ["DROP INDEX #{quote_ident(index_name)};"]
  end

  defp operation_to_sql({:recreate_generated_column, table_name, col_name, %Column{} = column}) do
    ["ALTER TABLE #{quote_ident(table_name)} DROP COLUMN #{quote_ident(col_name)};"] ++
      operation_to_sql({:add_column, table_name, column})
  end

  defp operation_to_sql({:execute_sql, sql}) when is_binary(sql) do
    [sql]
  end

  defp operation_to_sql(operation) do
    raise ArgumentError, "unsupported operation: #{inspect(operation)}"
  end

  defp alter_column_change_sql(_table_name, _column_name, {:type, :serial}) do
    raise ArgumentError,
          "Cannot change the type of an existing column to :serial. " <>
            "The :serial pseudo-type can only be used when creating a new column."
  end

  defp alter_column_change_sql(table_name, column_name, {:type, new_type}) do
    new_type_pg = pg_type_from_atom(new_type)

    "ALTER TABLE #{quote_ident(table_name)} ALTER COLUMN #{quote_ident(column_name)} TYPE #{new_type_pg} USING #{quote_ident(column_name)}::#{new_type_pg};"
  end

  defp alter_column_change_sql(table_name, column_name, {:null, false}) do
    "ALTER TABLE #{quote_ident(table_name)} ALTER COLUMN #{quote_ident(column_name)} SET NOT NULL;"
  end

  defp alter_column_change_sql(table_name, column_name, {:null, true}) do
    "ALTER TABLE #{quote_ident(table_name)} ALTER COLUMN #{quote_ident(column_name)} DROP NOT NULL;"
  end

  defp alter_column_change_sql(table_name, column_name, {:default, nil}) do
    "ALTER TABLE #{quote_ident(table_name)} ALTER COLUMN #{quote_ident(column_name)} DROP DEFAULT;"
  end

  defp alter_column_change_sql(table_name, column_name, {:default, value}) do
    "ALTER TABLE #{quote_ident(table_name)} ALTER COLUMN #{quote_ident(column_name)} SET DEFAULT #{render_default(value)};"
  end

  defp alter_column_change_sql(table_name, column_name, {:references, nil}) do
    "-- DROP FOREIGN KEY for #{quote_ident(table_name)}.#{quote_ident(column_name)} is not fully supported yet without constraint name"
  end

  defp alter_column_change_sql(table_name, column_name, {:references, ref_table}) do
    "ALTER TABLE #{quote_ident(table_name)} ADD FOREIGN KEY (#{quote_ident(column_name)}) REFERENCES #{quote_ident(ref_table)}(id);"
  end

  defp alter_column_change_sql(table_name, column_name, {:on_delete, action, referenced_table}) do
    on_delete_sql = fk_action_sql("DELETE", action)

    "-- Note: You must manually drop the old foreign key constraint for #{quote_ident(table_name)}.#{quote_ident(column_name)}\n" <>
      "ALTER TABLE #{quote_ident(table_name)} ADD FOREIGN KEY (#{quote_ident(column_name)}) REFERENCES #{quote_ident(referenced_table)}(id)#{on_delete_sql};"
  end

  defp alter_column_change_sql(table_name, column_name, {:on_update, action, referenced_table}) do
    on_update_sql = fk_action_sql("UPDATE", action)

    "-- Note: You must manually drop the old foreign key constraint for #{quote_ident(table_name)}.#{quote_ident(column_name)}\n" <>
      "ALTER TABLE #{quote_ident(table_name)} ADD FOREIGN KEY (#{quote_ident(column_name)}) REFERENCES #{quote_ident(referenced_table)}(id)#{on_update_sql};"
  end

  defp alter_column_change_sql(table_name, column_name, {:size, size, :string})
       when is_integer(size) and size > 0 do
    "ALTER TABLE #{quote_ident(table_name)} ALTER COLUMN #{quote_ident(column_name)} TYPE varchar(#{size});"
  end

  defp alter_column_change_sql(table_name, column_name, {:size, nil, :string}) do
    "ALTER TABLE #{quote_ident(table_name)} ALTER COLUMN #{quote_ident(column_name)} TYPE text;"
  end

  defp alter_column_change_sql(table_name, column_name, {:size, size, :vector})
       when is_integer(size) and size > 0 do
    "ALTER TABLE #{quote_ident(table_name)} ALTER COLUMN #{quote_ident(column_name)} TYPE vector(#{size});"
  end

  defp alter_column_change_sql(table_name, column_name, {:size, nil, :vector}) do
    "ALTER TABLE #{quote_ident(table_name)} ALTER COLUMN #{quote_ident(column_name)} TYPE vector;"
  end

  defp alter_column_change_sql(table_name, column_name, {:generated_as, nil}) do
    "ALTER TABLE #{quote_ident(table_name)} ALTER COLUMN #{quote_ident(column_name)} DROP EXPRESSION;"
  end

  defp alter_column_change_sql(_table_name, column_name, {:generated_as, {:fragment, _}}) do
    raise ArgumentError,
          "Cannot alter generated expression for column #{inspect(column_name)} in place. " <>
            "Use :recreate_generated_column operation instead (DROP + ADD)."
  end

  defp alter_column_change_sql(table_name, column_name, change) do
    raise ArgumentError,
          "unsupported alter_column change for #{inspect(table_name)}.#{inspect(column_name)}: #{inspect(change)}"
  end

  defp column_definition(%Column{} = column, table, pk_mode) do
    pk_frag = if pk_mode == :skip_pk, do: [], else: primary_key_fragment(column)

    ([quote_ident(column.name), pg_type(column, table)] ++
       pk_frag ++
       null_fragment(column) ++
       default_fragment(column) ++
       generated_as_fragment(column) ++
       references_fragment(column, table))
    |> Enum.join(" ")
  end

  defp primary_key_fragment(%Column{primary_key: true}), do: ["PRIMARY KEY"]
  defp primary_key_fragment(%Column{}), do: []

  defp null_fragment(%Column{null: false}), do: ["NOT NULL"]
  defp null_fragment(%Column{}), do: []

  defp default_fragment(%Column{default: nil}), do: []
  defp default_fragment(%Column{default: value}), do: ["DEFAULT #{render_default(value)}"]

  defp generated_as_fragment(%Column{generated_as: nil}), do: []

  defp generated_as_fragment(%Column{generated_as: {:fragment, expression}}) do
    ["GENERATED ALWAYS AS (#{expression}) STORED"]
  end

  defp references_fragment(%Column{references: nil}, _table_name), do: []

  defp references_fragment(%Column{references: table, name: column_name}, table_struct) do
    # Here table_struct is the Table where this column resides.
    # We need to find the ForeignKey struct to get on_delete rule.
    fk = Enum.find(table_struct.foreign_keys, &(&1.column_name == column_name))

    if fk do
      on_delete_sql = fk_action_sql("DELETE", fk.on_delete)
      on_update_sql = fk_action_sql("UPDATE", fk.on_update)

      ["REFERENCES #{quote_ident(fk.referenced_table)}(id)#{on_delete_sql}#{on_update_sql}"]
    else
      ["REFERENCES #{quote_ident(table)}(id)"]
    end
  end

  defp fk_action_sql(_verb, :nothing), do: ""
  defp fk_action_sql(verb, :cascade), do: " ON #{verb} CASCADE"
  defp fk_action_sql(verb, :delete_all), do: " ON #{verb} CASCADE"
  defp fk_action_sql(verb, :update_all), do: " ON #{verb} CASCADE"
  defp fk_action_sql(verb, :restrict), do: " ON #{verb} RESTRICT"
  defp fk_action_sql(verb, :set_null), do: " ON #{verb} SET NULL"
  defp fk_action_sql(verb, :nilify_all), do: " ON #{verb} SET NULL"

  defp quote_ident(value) when is_atom(value), do: value |> Atom.to_string() |> quote_ident()

  defp quote_ident(value) when is_binary(value) do
    escaped = String.replace(value, "\"", "\"\"")
    "\"#{escaped}\""
  end

  defp pg_type(%Column{type: :vector, size: size}, _table) when is_integer(size) and size > 0 do
    "vector(#{size})"
  end

  defp pg_type(%Column{type: :string, size: size}, _table) when is_integer(size) and size > 0 do
    "varchar(#{size})"
  end

  defp pg_type(%Column{type: type, enum: enum_values} = column, table) do
    if enum_values != nil do
      table_name = if is_atom(table), do: table, else: table.name
      quote_ident("#{table_name}_#{column.name}_enum")
    else
      pg_type_from_atom(type)
    end
  end

  defp pg_type_from_atom(:string), do: "text"
  defp pg_type_from_atom(:text), do: "text"
  defp pg_type_from_atom(:integer), do: "integer"
  defp pg_type_from_atom(:int), do: "integer"
  defp pg_type_from_atom(:bigint), do: "bigint"
  defp pg_type_from_atom(:bigserial), do: "bigserial"
  defp pg_type_from_atom(:smallint), do: "smallint"
  defp pg_type_from_atom(:uuid), do: "uuid"
  defp pg_type_from_atom(:serial), do: "serial"
  defp pg_type_from_atom(:boolean), do: "boolean"
  defp pg_type_from_atom(:bool), do: "boolean"
  defp pg_type_from_atom(:float), do: "double precision"
  defp pg_type_from_atom(:decimal), do: "numeric"
  defp pg_type_from_atom(:date), do: "date"
  defp pg_type_from_atom(:time), do: "time"
  defp pg_type_from_atom(:naive_datetime), do: "timestamp without time zone"
  defp pg_type_from_atom(:utc_datetime), do: "timestamp with time zone"
  defp pg_type_from_atom(:binary), do: "bytea"
  defp pg_type_from_atom(:binary_id), do: "bytea"
  defp pg_type_from_atom(:map), do: "jsonb"
  defp pg_type_from_atom(:vector), do: "vector"
  defp pg_type_from_atom(:tsvector), do: "tsvector"
  defp pg_type_from_atom(:citext), do: "citext"

  defp pg_type_from_atom(type) do
    raise ArgumentError, "unsupported postgres type: #{inspect(type)}"
  end

  defp render_default({:fragment, sql}) when is_binary(sql), do: sql

  defp render_default({:fragment, sql}) do
    raise ArgumentError, "unsupported fragment default value: #{inspect(sql)}"
  end

  defp render_default(value) when is_binary(value) do
    escaped = String.replace(value, "'", "''")
    "'#{escaped}'"
  end

  defp render_default(true), do: "TRUE"
  defp render_default(false), do: "FALSE"

  defp render_default(value) when is_number(value), do: to_string(value)

  defp render_default(value) do
    raise ArgumentError, "unsupported default value: #{inspect(value)}"
  end
end
