defmodule PgPushex.Introspector.Postgres do
  @moduledoc """
  Reads the current database schema from PostgreSQL system catalogs.

  This module queries PostgreSQL's `information_schema` and `pg_catalog`
  to extract the current database structure including:

  - Tables and their columns with types, defaults, and constraints
  - Primary keys and foreign key relationships
  - Indexes (including uniqueness constraints)
  - Custom ENUM types
  - Installed extensions
  - Generated columns

  The introspected state is returned as a `PgPushex.State.Schema` struct
  that can be compared with the desired state from `PgPushex.Schema` DSL.
  """

  require Logger

  alias PgPushex.State.{Column, Index, Schema, Table}

  @column_metadata_sql """
  SELECT
    c.table_name,
    c.column_name,
    c.data_type,
    c.udt_name,
    c.is_nullable,
    c.column_default,
    c.is_identity,
    c.character_maximum_length,
    EXISTS (
      SELECT 1
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu
        ON tc.constraint_schema = kcu.constraint_schema
       AND tc.constraint_name = kcu.constraint_name
       AND tc.table_schema = kcu.table_schema
       AND tc.table_name = kcu.table_name
      WHERE tc.constraint_type = 'PRIMARY KEY'
        AND tc.table_schema = c.table_schema
        AND tc.table_name = c.table_name
        AND kcu.column_name = c.column_name
    ) AS is_primary_key,
    (
      SELECT a.atttypmod
      FROM pg_attribute a
      JOIN pg_class pc ON pc.oid = a.attrelid
      JOIN pg_namespace ns ON ns.oid = pc.relnamespace
      WHERE pc.relname = c.table_name
        AND ns.nspname = c.table_schema
        AND a.attname = c.column_name
        AND a.attnum > 0
    ) AS atttypmod,
    c.generation_expression
  FROM information_schema.columns c
  JOIN information_schema.tables t
    ON t.table_schema = c.table_schema
   AND t.table_name = c.table_name
  WHERE c.table_schema = 'public'
    AND t.table_type = 'BASE TABLE'
    AND c.table_name <> 'schema_migrations'
  ORDER BY c.table_name, c.ordinal_position
  """

  @enum_values_sql """
  SELECT t.typname, e.enumlabel
  FROM pg_type t
  JOIN pg_enum e ON t.oid = e.enumtypid
  ORDER BY e.enumsortorder
  """

  @index_metadata_sql """
  SELECT
    i.tablename,
    i.indexname,
    ix.indisunique,
    array_agg(a.attname ORDER BY array_position(ix.indkey, a.attnum)) AS columns
  FROM pg_indexes i
  JOIN pg_class c ON c.relname = i.indexname
  JOIN pg_index ix ON ix.indexrelid = c.oid
  JOIN pg_attribute a ON a.attrelid = ix.indrelid AND a.attnum = ANY(ix.indkey)
  WHERE i.schemaname = 'public'
    AND ix.indisprimary = false
  GROUP BY i.tablename, i.indexname, ix.indisunique
  ORDER BY i.tablename, i.indexname
  """

  @fk_metadata_sql """
  SELECT
    kcu.table_name,
    kcu.column_name,
    ccu.table_name AS referenced_table,
    rc.delete_rule,
    rc.update_rule
  FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
   AND tc.table_schema = kcu.table_schema
  JOIN information_schema.constraint_column_usage ccu
    ON ccu.constraint_name = tc.constraint_name
   AND ccu.table_schema = tc.table_schema
  JOIN information_schema.referential_constraints rc
    ON rc.constraint_name = tc.constraint_name
   AND rc.constraint_schema = tc.constraint_schema
  WHERE tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_schema = 'public'
  """

  @extensions_sql "SELECT extname FROM pg_extension"

  @unsupported_source_error "introspect/1 expects an Ecto.Repo module or Postgrex connection pid"

  @doc """
  Introspects the current database schema.

  Queries PostgreSQL system catalogs to build a complete representation
  of the current database structure.

  ## Parameters

  - `repo_or_conn` - An Ecto.Repo module or a Postgrex connection pid

  ## Returns

  A `%PgPushex.State.Schema{}` struct containing all tables, columns,
  indexes, foreign keys, and extensions found in the database.

  ## Examples

      schema = PgPushex.Introspector.Postgres.introspect(MyApp.Repo)
      tables = Map.keys(schema.tables)
  """
  @spec introspect(module() | pid()) :: Schema.t()
  def introspect(repo_or_conn) do
    enum_map = load_enum_values(repo_or_conn)
    index_map = load_indexes(repo_or_conn)
    fk_map = load_foreign_keys(repo_or_conn)
    extensions = load_extensions(repo_or_conn)

    repo_or_conn
    |> query!(@column_metadata_sql)
    |> result_to_schema(enum_map, index_map, fk_map, extensions)
  end

  defp query!(repo, sql) when is_atom(repo) do
    if function_exported?(repo, :__adapter__, 0) do
      Ecto.Adapters.SQL.query!(repo, sql, [])
    else
      raise ArgumentError, "#{@unsupported_source_error}, got: #{inspect(repo)}"
    end
  end

  defp query!(conn_pid, sql) when is_pid(conn_pid), do: Postgrex.query!(conn_pid, sql, [])

  defp query!(value, _sql) do
    raise ArgumentError, "#{@unsupported_source_error}, got: #{inspect(value)}"
  end

  defp load_enum_values(repo_or_conn) do
    %{rows: rows} = query!(repo_or_conn, @enum_values_sql)
    Enum.group_by(rows, fn [typname, _] -> typname end, fn [_, label] -> label end)
  end

  defp load_indexes(repo_or_conn) do
    %{rows: rows} = query!(repo_or_conn, @index_metadata_sql)

    rows
    |> Enum.map(fn [tablename, indexname, is_unique, columns] ->
      {tablename,
       %Index{
         name: String.to_atom(indexname),
         columns: Enum.map(columns, &String.to_atom/1),
         unique: is_unique
       }}
    end)
    |> Enum.group_by(fn {table, _} -> table end, fn {_, index} -> index end)
  end

  defp load_extensions(repo_or_conn) do
    %{rows: rows} = query!(repo_or_conn, @extensions_sql)
    Enum.map(rows, fn [extname] -> extname end)
  end

  defp load_foreign_keys(repo_or_conn) do
    %{rows: rows} = query!(repo_or_conn, @fk_metadata_sql)

    rows
    |> Enum.group_by(fn [table_name, _, _, _, _] -> table_name end)
    |> Map.new(fn {table_name, fk_rows} ->
      col_refs =
        Map.new(fk_rows, fn [_, col_name, ref_table, delete_rule, update_rule] ->
          {col_name, {ref_table, parse_action_rule(delete_rule), parse_action_rule(update_rule)}}
        end)

      {table_name, col_refs}
    end)
  end

  defp parse_action_rule("CASCADE"), do: :cascade
  defp parse_action_rule("SET NULL"), do: :set_null
  defp parse_action_rule("RESTRICT"), do: :restrict
  defp parse_action_rule(_), do: :nothing

  defp result_to_schema(%{columns: columns, rows: rows}, enum_map, index_map, fk_map, extensions) do
    tables =
      rows
      |> Enum.map(&row_to_metadata(columns, &1, enum_map))
      |> Enum.reject(&is_nil/1)
      |> Enum.group_by(& &1.table_name, & &1.column)
      |> Enum.map(fn {table_name, table_columns} ->
        table_name_str = Atom.to_string(table_name)
        indexes = Map.get(index_map, table_name_str, [])
        table_fks_map = Map.get(fk_map, table_name_str, %{})

        enriched_columns =
          Enum.map(table_columns, fn col ->
            case Map.get(table_fks_map, Atom.to_string(col.name)) do
              nil ->
                col

              {ref_table, delete_rule, update_rule} ->
                %{
                  col
                  | references: String.to_atom(ref_table),
                    on_delete: delete_rule,
                    on_update: update_rule
                }
            end
          end)

        foreign_keys =
          table_fks_map
          |> Enum.map(fn {col_name, {ref_table, delete_rule, update_rule}} ->
            %PgPushex.State.ForeignKey{
              column_name: String.to_atom(col_name),
              referenced_table: String.to_atom(ref_table),
              referenced_column: :id,
              on_delete: delete_rule,
              on_update: update_rule
            }
          end)

        %Table{
          name: table_name,
          columns: enriched_columns,
          foreign_keys: foreign_keys,
          indexes: indexes
        }
      end)
      |> Enum.sort_by(&Atom.to_string(&1.name))

    %Schema{tables: Map.new(tables, &{&1.name, &1}), extensions: extensions}
  end

  defp row_to_metadata(columns, row, enum_map) do
    row_map = Map.new(Enum.zip(columns, row))

    table_name_str = Map.fetch!(row_map, "table_name")
    column_name_str = Map.fetch!(row_map, "column_name")
    data_type = Map.fetch!(row_map, "data_type")
    udt_name = Map.get(row_map, "udt_name")
    default = Map.get(row_map, "column_default")
    identity = identity?(Map.get(row_map, "is_identity"))
    char_max_length = Map.get(row_map, "character_maximum_length")
    atttypmod = Map.get(row_map, "atttypmod")
    generation_expression = Map.get(row_map, "generation_expression")

    {type_result, enum_values} =
      resolve_column_type(data_type, default, identity, udt_name, enum_map)

    case type_result do
      {:ok, type} ->
        table_name = String.to_atom(table_name_str)
        column_name = String.to_atom(column_name_str)
        nullable = nullable?(Map.fetch!(row_map, "is_nullable"))
        primary_key = truthy?(Map.get(row_map, "is_primary_key"))

        size =
          cond do
            type == :string and char_max_length -> char_max_length
            type == :vector and is_integer(atttypmod) and atttypmod > 0 -> atttypmod
            true -> nil
          end

        generated_as =
          case generation_expression do
            nil -> nil
            "" -> nil
            expr -> {:fragment, expr}
          end

        column = %Column{
          name: column_name,
          type: type,
          null: nullable,
          default: parse_default(default, type, identity, primary_key),
          primary_key: primary_key,
          enum: enum_values,
          size: size,
          generated_as: generated_as
        }

        %{table_name: table_name, column: column}

      :skip ->
        Logger.warning(
          "Skipping column with unsupported type '#{data_type}': #{table_name_str}.#{column_name_str}"
        )

        nil
    end
  end

  defp resolve_column_type("USER-DEFINED", _default, _identity, "vector", _enum_map) do
    {{:ok, :vector}, nil}
  end

  defp resolve_column_type("USER-DEFINED", _default, _identity, udt_name, enum_map) do
    case Map.get(enum_map, udt_name) do
      nil -> {:skip, nil}
      values -> {{:ok, :string}, values}
    end
  end

  defp resolve_column_type(data_type, default, identity, _udt_name, _enum_map) do
    {map_column_type(data_type, default, identity), nil}
  end

  defp map_column_type("integer", default, identity) do
    if identity or sequence_default?(default), do: {:ok, :serial}, else: {:ok, :integer}
  end

  defp map_column_type("bigint", default, identity) do
    if identity or sequence_default?(default), do: {:ok, :bigserial}, else: {:ok, :bigint}
  end

  defp map_column_type("smallint", _default, _identity), do: {:ok, :smallint}

  defp map_column_type("text", _default, _identity), do: {:ok, :string}
  defp map_column_type("character varying", _default, _identity), do: {:ok, :string}
  defp map_column_type("uuid", _default, _identity), do: {:ok, :uuid}
  defp map_column_type("boolean", _default, _identity), do: {:ok, :boolean}
  defp map_column_type("double precision", _default, _identity), do: {:ok, :float}
  defp map_column_type("numeric", _default, _identity), do: {:ok, :decimal}
  defp map_column_type("date", _default, _identity), do: {:ok, :date}
  defp map_column_type("time without time zone", _default, _identity), do: {:ok, :time}

  defp map_column_type("timestamp without time zone", _default, _identity),
    do: {:ok, :naive_datetime}

  defp map_column_type("timestamp with time zone", _default, _identity), do: {:ok, :utc_datetime}
  defp map_column_type("bytea", _default, _identity), do: {:ok, :binary}
  defp map_column_type("jsonb", _default, _identity), do: {:ok, :map}
  defp map_column_type(_type, _default, _identity), do: :skip

  defp parse_default(_default, :serial, _identity, _primary_key), do: nil
  defp parse_default(_default, _type, true, _primary_key), do: nil
  defp parse_default(nil, _type, _identity, _primary_key), do: nil

  defp parse_default(default, _type, _identity, primary_key)
       when primary_key and is_binary(default) do
    if sequence_default?(default), do: nil, else: parse_literal_or_expression(default)
  end

  defp parse_default(default, _type, _identity, _primary_key),
    do: parse_literal_or_expression(default)

  defp parse_literal_or_expression(default) do
    expression = normalize_default_expression(default)

    case parse_literal(expression) do
      {:ok, value} -> value
      :error -> {:fragment, expression}
    end
  end

  defp parse_literal(expression) do
    with :error <- parse_boolean_literal(expression),
         :error <- parse_numeric_literal(expression),
         :error <- parse_string_literal(expression) do
      :error
    end
  end

  defp parse_boolean_literal(expression) do
    expression_without_cast = strip_type_cast(expression)
    has_cast? = expression_without_cast != expression

    cond do
      has_cast? and not boolean_cast?(expression) ->
        :error

      true ->
        case String.downcase(expression_without_cast) do
          "true" -> {:ok, true}
          "false" -> {:ok, false}
          "'t'" -> {:ok, true}
          "'f'" -> {:ok, false}
          "'true'" -> {:ok, true}
          "'false'" -> {:ok, false}
          _ -> :error
        end
    end
  end

  defp parse_numeric_literal(expression) do
    expression_without_cast = strip_type_cast(expression)

    cond do
      Regex.match?(~r/^-?\d+$/, expression_without_cast) ->
        {:ok, String.to_integer(expression_without_cast)}

      Regex.match?(~r/^-?\d+\.\d+$/, expression_without_cast) ->
        {:ok, String.to_float(expression_without_cast)}

      true ->
        :error
    end
  end

  defp parse_string_literal(expression) do
    case Regex.run(~r/^'((?:[^']|'')*)'(?:\s*::.+)?$/s, expression, capture: :all_but_first) do
      [value] -> {:ok, String.replace(value, "''", "'")}
      _ -> :error
    end
  end

  defp nullable?("YES"), do: true
  defp nullable?("NO"), do: false

  defp nullable?(value) do
    raise ArgumentError, "Unexpected is_nullable value from PostgreSQL: #{inspect(value)}"
  end

  defp identity?("YES"), do: true
  defp identity?("NO"), do: false
  defp identity?(nil), do: false

  defp identity?(value) do
    raise ArgumentError, "Unexpected is_identity value from PostgreSQL: #{inspect(value)}"
  end

  defp truthy?(value) when value in [true, "t", "true", 1], do: true
  defp truthy?(_value), do: false

  defp sequence_default?(default) when is_binary(default) do
    default
    |> normalize_default_expression()
    |> String.downcase()
    |> String.starts_with?("nextval(")
  end

  defp sequence_default?(_default), do: false

  defp boolean_cast?(expression) do
    expression
    |> String.downcase()
    |> String.ends_with?("::boolean")
  end

  defp strip_type_cast(expression) do
    expression
    |> String.replace(~r/::[a-zA-Z0-9_\s\.\[\]"]+$/, "")
    |> String.trim()
  end

  defp normalize_default_expression(expression) do
    expression
    |> String.trim()
    |> unwrap_outer_parentheses()
  end

  defp unwrap_outer_parentheses(expression) do
    trimmed = String.trim(expression)

    case Regex.run(~r/^\((.*)\)$/s, trimmed, capture: :all_but_first) do
      [inner] -> unwrap_outer_parentheses(inner)
      _ -> trimmed
    end
  end
end
