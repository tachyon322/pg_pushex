defmodule PgPushex.MigrationGenerator do
  @moduledoc """
  Generates Ecto migration code from diff operations.

  This module converts the operations produced by `PgPushex.Diff` into
  valid Elixir code for Ecto migrations. It handles:

  - Creating and dropping tables
  - Adding, removing, and modifying columns
  - Creating and dropping indexes
  - PostgreSQL-specific features (enums, generated columns, extensions)
  - Grouping alter operations for efficiency

  The generated code follows Ecto migration conventions and can be written
  directly to a migration file.
  """

  alias PgPushex.State.{Column, Table}

  @typedoc """
  A diff operation to be rendered as migration code.

  See `PgPushex.Diff.operation/0` for the full list of operation types.
  """
  @type operation :: PgPushex.Diff.operation()

  @doc """
  Generates a complete Ecto migration module as a string.

  Takes the repository module, a list of operations from `PgPushex.Diff.compare/2`,
  and options to produce a complete migration file content.

  ## Parameters

  - `repo` - The Ecto repository module (used for module naming)
  - `operations` - List of diff operations to convert
  - `opts` - Keyword options:
    - `:suffix` - Module name suffix (default: "PgPushexPush")

  ## Returns

  A string containing the complete migration module code.

  ## Examples

      operations = PgPushex.Diff.compare(current_state, desired_state)
      migration_code = PgPushex.MigrationGenerator.generate(MyApp.Repo, operations)
      File.write!("priv/repo/migrations/20240101120000_pg_pushex_push.exs", migration_code)
  """
  @spec generate(module(), [operation()], keyword()) :: String.t()
  def generate(repo, operations, opts \\ []) do
    suffix = Keyword.get(opts, :suffix, "PgPushexPush")
    module_name = migration_module_name(repo, suffix)
    body = render_body(operations)

    """
    defmodule #{module_name} do
      use Ecto.Migration

      def change do
    #{body}
      end
    end
    """
    |> String.trim_trailing()
    |> Kernel.<>("\n")
  end

  @doc false
  defp migration_module_name(repo, suffix) do
    "#{inspect(repo)}.Migrations.#{suffix}"
  end

  @doc false
  defp render_body(operations) do
    operations
    |> group_alter_operations()
    |> Enum.map(&render_operation/1)
    |> Enum.join("\n\n")
  end

  @doc false
  defp group_alter_operations(operations) do
    operations
    |> Enum.chunk_while(
      nil,
      fn op, acc ->
        case {acc, classify(op)} do
          {nil, {:alter, table_name}} ->
            {:cont, {table_name, [op]}}

          {{table_name, ops}, {:alter, table_name}} ->
            {:cont, {table_name, ops ++ [op]}}

          {{_table_name, _ops} = group, _} ->
            {:cont, group, classify_init(op)}

          {nil, _} ->
            {:cont, {:single, op}}
        end
      end,
      fn
        nil -> {:cont, nil}
        acc -> {:cont, acc, nil}
      end
    )
    |> Enum.reject(&is_nil/1)
  end

  @doc false
  defp classify({:add_column, table, _col}), do: {:alter, table}
  defp classify({:drop_column, table, _col}), do: {:alter, table}
  defp classify({:alter_column, table, _col, _changes}), do: {:alter, table}
  defp classify(_op), do: :other

  @doc false
  defp classify_init(op) do
    case classify(op) do
      {:alter, table_name} -> {table_name, [op]}
      :other -> {:single, op}
    end
  end

  @doc false
  defp render_operation({:single, op}), do: render_single(op)

  @doc false
  defp render_operation({_table_name, ops}) when is_list(ops) do
    table = elem(hd(ops), 1)

    inner =
      ops
      |> Enum.map(&render_alter_inner/1)
      |> Enum.join("\n")

    indent("""
    alter table(:#{table}) do
    #{inner}
    end\
    """)
  end

  @doc false
  defp render_alter_inner({:add_column, _table, %Column{} = col}) do
    if col.references do
      ref_expr = build_references_expr(col, nil)
      opts = column_opts(col)
      "      add :#{col.name}, #{ref_expr}#{opts}"
    else
      opts = column_opts(col)
      "      add :#{col.name}, #{type_expr(col)}#{opts}"
    end
  end

  @doc false
  defp render_alter_inner({:drop_column, _table, col_name}) do
    "      remove :#{col_name}"
  end

  @doc false
  defp render_alter_inner({:alter_column, _table, col_name, changes}) do
    opts = alter_opts(changes)
    type = Keyword.get(changes, :type)
    type_str = if type, do: ":#{type}", else: ":string"
    "      modify :#{col_name}, #{type_str}#{opts}"
  end

  @doc false
  defp render_single({:create_table, _name, %Table{} = table}) do
    columns =
      table.columns
      |> Enum.map(&render_create_column(&1, table))
      |> Enum.join("\n")

    indent("""
    create table(:#{table.name}, primary_key: false) do
    #{columns}
    end\
    """)
    |> maybe_append_indexes(table.name, table.indexes)
  end

  @doc false
  defp render_single({:drop_table, name}) do
    indent("drop table(:#{name})")
  end

  @doc false
  defp render_single({:rename_column, table, old_name, new_name}) do
    indent("rename table(:#{table}), :#{old_name}, to: :#{new_name}")
  end

  @doc false
  defp render_single({:create_index, table, index}) do
    render_index(table, index)
  end

  @doc false
  defp render_single({:drop_index, table, index_name}) do
    indent("drop index(:#{table}, name: :#{index_name})")
  end

  @doc false
  defp render_single({:create_type_enum, enum_name, values}) do
    values_str = Enum.map(values, &"'#{&1}'") |> Enum.join(", ")
    indent("execute \"CREATE TYPE \\\"#{enum_name}\\\" AS ENUM (#{values_str})\"")
  end

  @doc false
  defp render_single({:alter_enum, enum_name, added_values}) do
    added_values
    |> Enum.map(fn value ->
      indent("execute \"ALTER TYPE \\\"#{enum_name}\\\" ADD VALUE IF NOT EXISTS '#{value}'\"")
    end)
    |> Enum.join("\n\n")
  end

  @doc false
  defp render_single({:recreate_generated_column, table, col_name, %Column{} = col}) do
    {:fragment, expr} = col.generated_as
    escaped = String.replace(expr, "\"", "\\\"")

    drop = indent("execute \"ALTER TABLE \\\"#{table}\\\" DROP COLUMN \\\"#{col_name}\\\"\"")

    add =
      indent(
        "execute \"ALTER TABLE \\\"#{table}\\\" ADD COLUMN \\\"#{col_name}\\\" #{pg_type(col)} #{null_opt_raw(col)}GENERATED ALWAYS AS (#{escaped}) STORED\""
      )

    drop <> "\n\n" <> add
  end

  @doc false
  defp render_single({:execute_sql, sql}) do
    escaped = String.replace(sql, "\"", "\\\"")
    indent("execute \"#{escaped}\"")
  end

  @doc false
  defp render_single(op) do
    indent("# Unsupported operation: #{inspect(op)}")
  end

  @doc false
  defp render_create_column(%Column{} = col, table) do
    cond do
      col.generated_as != nil ->
        {:fragment, expr} = col.generated_as
        escaped = String.replace(expr, "\"", "\\\"")

        "      execute \"ALTER TABLE \\\"#{table.name}\\\" ADD COLUMN \\\"#{col.name}\\\" #{pg_type(col)} #{null_opt_raw(col)}GENERATED ALWAYS AS (#{escaped}) STORED\""

      col.references != nil ->
        fk = Enum.find(table.foreign_keys, &(&1.column_name == col.name))
        ref_expr = build_references_expr(col, fk)
        opts = column_opts(col)
        "      add :#{col.name}, #{ref_expr}#{opts}"

      true ->
        opts = column_opts(col)
        "      add :#{col.name}, #{type_expr(col)}#{opts}"
    end
  end

  @doc false
  defp render_index(table, index) do
    cols = Enum.map(index.columns, &":#{&1}") |> Enum.join(", ")

    if index.unique do
      indent("create unique_index(:#{table}, [#{cols}], name: :#{index.name})")
    else
      indent("create index(:#{table}, [#{cols}], name: :#{index.name})")
    end
  end

  @doc false
  defp maybe_append_indexes(str, _table, []), do: str

  @doc false
  defp maybe_append_indexes(str, table, indexes) do
    idx_strs = Enum.map(indexes, &render_index(table, &1))
    str <> "\n\n" <> Enum.join(idx_strs, "\n\n")
  end

  @doc false
  defp type_expr(%Column{enum: values}) when is_list(values) and values != [] do
    ":string"
  end

  @doc false
  defp type_expr(%Column{type: :serial}), do: ":serial"

  defp type_expr(%Column{type: :string, size: size}) when is_integer(size) and size > 0,
    do: ":string"

  defp type_expr(%Column{type: :vector, size: size}) when is_integer(size) and size > 0,
    do: "\"vector(#{size})\""

  defp type_expr(%Column{type: type}), do: ":#{type}"

  @doc false
  defp column_opts(%Column{} = col) do
    opts = []
    opts = if col.null == false and not col.primary_key, do: opts ++ [null: false], else: opts
    opts = if col.primary_key, do: opts ++ [primary_key: true], else: opts

    opts =
      case col.size do
        size when is_integer(size) and size > 0 and col.type == :string ->
          opts ++ [size: size]

        _ ->
          opts
      end

    opts =
      case col.default do
        nil -> opts
        {:fragment, sql} -> opts ++ [{:default, {:fragment, sql}}]
        val -> opts ++ [default: val]
      end

    if opts == [] do
      ""
    else
      ", " <> render_opts(opts)
    end
  end

  @doc false
  defp alter_opts(changes) do
    opts =
      changes
      |> Enum.reject(fn change -> elem(change, 0) == :type end)
      |> Enum.flat_map(fn
        {:null, val} -> [null: val]
        {:default, nil} -> [default: nil]
        {:default, {:fragment, sql}} -> [{:default, {:fragment, sql}}]
        {:default, val} -> [default: val]
        {:size, val, _type} -> [size: val]
        {:generated_as, _} -> []
        {:references, _} -> []
        {:on_delete, _, _, _, _} -> []
        {:on_update, _, _, _, _} -> []
        _ -> []
      end)

    if opts == [] do
      ""
    else
      ", " <> render_opts(opts)
    end
  end

  @doc false
  defp render_opts(opts) do
    Enum.map_join(opts, ", ", fn
      {:default, {:fragment, sql}} ->
        escaped = String.replace(sql, "\"", "\\\"")
        "default: fragment(\"#{escaped}\")"

      {:default, nil} ->
        "default: nil"

      {:default, val} when is_binary(val) ->
        "default: \"#{val}\""

      {:default, val} ->
        "default: #{inspect(val)}"

      {key, val} ->
        "#{key}: #{inspect(val)}"
    end)
  end

  @doc false
  defp build_references_expr(%Column{} = col, fk) do
    ref_type = reference_type(col.type)
    ref_opts = ["type: :#{ref_type}"]

    # Add referenced_column if it's not the default :id
    ref_opts =
      if fk && fk.referenced_column && fk.referenced_column != :id do
        ref_opts ++ ["column: :#{fk.referenced_column}"]
      else
        ref_opts
      end

    ref_opts =
      if fk && ecto_fk_action(fk.on_delete) do
        ref_opts ++ ["on_delete: :#{ecto_fk_action(fk.on_delete)}"]
      else
        ref_opts
      end

    ref_opts =
      if fk && ecto_fk_action(fk.on_update) do
        ref_opts ++ ["on_update: :#{ecto_fk_action(fk.on_update)}"]
      else
        ref_opts
      end

    "references(:#{col.references}, #{Enum.join(ref_opts, ", ")})"
  end

  @doc false
  defp reference_type(:serial), do: :integer
  defp reference_type(:int), do: :integer
  defp reference_type(type), do: type

  @doc false
  defp ecto_fk_action(:cascade), do: :delete_all
  defp ecto_fk_action(:delete_all), do: :delete_all
  defp ecto_fk_action(:set_null), do: :nilify_all
  defp ecto_fk_action(:nilify_all), do: :nilify_all
  defp ecto_fk_action(:restrict), do: :restrict
  defp ecto_fk_action(:update_all), do: :update_all
  defp ecto_fk_action(_), do: nil

  @doc false
  defp null_opt_raw(%Column{null: false}), do: "NOT NULL "
  defp null_opt_raw(_), do: ""

  @doc false
  defp pg_type(%Column{type: :string, size: nil}), do: "text"
  defp pg_type(%Column{type: :string, size: size}) when is_integer(size), do: "varchar(#{size})"
  defp pg_type(%Column{type: :text}), do: "text"
  defp pg_type(%Column{type: :integer}), do: "integer"
  defp pg_type(%Column{type: :int}), do: "integer"
  defp pg_type(%Column{type: :bigint}), do: "bigint"
  defp pg_type(%Column{type: :bigserial}), do: "bigserial"
  defp pg_type(%Column{type: :smallint}), do: "smallint"
  defp pg_type(%Column{type: :serial}), do: "serial"
  defp pg_type(%Column{type: :uuid}), do: "uuid"
  defp pg_type(%Column{type: :boolean}), do: "boolean"
  defp pg_type(%Column{type: :bool}), do: "boolean"
  defp pg_type(%Column{type: :float}), do: "double precision"

  defp pg_type(%Column{type: :decimal, precision: p, scale: s})
       when is_integer(p) and is_integer(s) and p > 0 and s >= 0,
       do: "numeric(#{p},#{s})"

  defp pg_type(%Column{type: :decimal}), do: "numeric"
  defp pg_type(%Column{type: :date}), do: "date"
  defp pg_type(%Column{type: :time}), do: "time"
  defp pg_type(%Column{type: :naive_datetime}), do: "timestamp without time zone"
  defp pg_type(%Column{type: :utc_datetime}), do: "timestamp with time zone"
  defp pg_type(%Column{type: :binary}), do: "bytea"
  defp pg_type(%Column{type: :binary_id}), do: "bytea"
  defp pg_type(%Column{type: :map}), do: "jsonb"
  defp pg_type(%Column{type: :vector, size: nil}), do: "vector"
  defp pg_type(%Column{type: :vector, size: size}), do: "vector(#{size})"
  defp pg_type(%Column{type: :tsvector}), do: "tsvector"
  defp pg_type(%Column{type: :citext}), do: "citext"

  @doc false
  defp indent(str) do
    str
    |> String.split("\n")
    |> Enum.map_join("\n", &("    " <> &1))
  end
end
