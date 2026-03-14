defmodule PgPushex.Diff do
  @moduledoc """
  Compares desired schema with current database state and produces operations.

  This module is the core of PgPushex's migration planning. It takes two
  schema states (current from database introspection, desired from DSL)
  and calculates the minimal set of operations needed to synchronize them.

  ## Operation Types

  The following operations can be produced:

  - `{:create_extension, name}` - Create a PostgreSQL extension
  - `{:create_table, name, table}` - Create a new table
  - `{:drop_table, name}` - Remove a table
  - `{:add_column, table, column}` - Add a column to existing table
  - `{:drop_column, table, column}` - Remove a column
  - `{:alter_column, table, column, changes}` - Modify column properties
  - `{:rename_column, table, old, new}` - Rename a column
  - `{:create_index, table, index}` - Create an index
  - `{:drop_index, table, name}` - Remove an index
  - `{:create_type_enum, name, values}` - Create an enum type
  - `{:alter_enum, name, new_values}` - Add values to existing enum
  - `{:recreate_generated_column, table, name, column}` - Recreate generated column
  - `{:execute_sql, sql}` - Execute raw SQL

  ## Rename Detection

  When columns are dropped and added in the same table, the diff produces
  a `{:check_column_renames, table, dropped, added}` operation. This allows
  interactive resolution to determine if it's a rename vs drop+create.
  """

  alias PgPushex.State.{Column, Schema, Table}

  @typedoc """
  A single change to a column property.
  """
  @type column_change ::
          {:type, Column.data_type()}
          | {:null, boolean()}
          | {:default, term()}
          | {:references, Column.references_table()}

  @typedoc """
  An operation representing a schema change.
  """
  @type operation ::
          {:create_extension, String.t()}
          | {:create_table, Table.name(), Table.t()}
          | {:drop_table, Table.name()}
          | {:add_column, Table.name(), Column.t()}
          | {:drop_column, Table.name(), Column.name()}
          | {:alter_column, Table.name(), Column.name(), [column_change()]}
          | {:recreate_generated_column, Table.name(), Column.name(), Column.t()}
          | {:check_column_renames, Table.name(), [Column.t()], [Column.t()]}
          | {:create_index, Table.name(), PgPushex.State.Index.t()}
          | {:drop_index, Table.name(), atom() | String.t()}
          | {:create_type_enum, String.t(), [String.t()]}
          | {:alter_enum, String.t(), [String.t()]}
          | {:execute_sql, String.t()}

  @doc """
  Compares current and desired schema states and returns operations.

  Takes the current database state (from introspection) and the desired
  state (from schema DSL) and produces a list of operations to apply.

  Operations are returned in dependency order:
  1. Extensions
  2. Raw SQL
  3. Enum types
  4. Table creations (topologically sorted by FK dependencies)
  5. Table drops (reverse dependency order)
  6. Table modifications (columns and indexes)

  ## Parameters

  - `current` - Current database state as `%PgPushex.State.Schema{}`
  - `desired` - Desired schema state as `%PgPushex.State.Schema{}`

  ## Returns

  List of operations that can be passed to `PgPushex.SQL.Postgres.generate/1`
  or `PgPushex.MigrationGenerator.generate/3`.

  ## Examples

      current = PgPushex.Introspector.Postgres.introspect(MyApp.Repo)
      desired = MyApp.Schema.__schema__()
      operations = PgPushex.Diff.compare(current, desired)
  """
  @spec compare(Schema.t(), Schema.t()) :: [operation()]
  def compare(
        %Schema{tables: current_tables} = current,
        %Schema{tables: desired_tables} = desired
      ) do
    raw_sql_ops = Enum.map(Map.get(desired, :raw_sqls, []), &{:execute_sql, &1})

    current_extensions = Map.get(current, :extensions, [])
    desired_extensions = Map.get(desired, :extensions, [])
    extension_ops = build_extension_ops(current_extensions, desired_extensions)

    enum_ops = build_enum_ops(current_tables, desired_tables)
    create_table_ops = build_create_table_ops(current_tables, desired_tables)
    drop_table_ops = build_drop_table_ops(current_tables, desired_tables)

    table_change_ops =
      current_tables
      |> common_table_names(desired_tables)
      |> Enum.flat_map(fn table_name ->
        compare_table(
          Map.fetch!(current_tables, table_name),
          Map.fetch!(desired_tables, table_name)
        )
      end)

    extension_ops ++
      raw_sql_ops ++ enum_ops ++ create_table_ops ++ drop_table_ops ++ table_change_ops
  end

  @doc """
  Calculates changes between two column definitions.

  Returns a list of `t:column_change/0` tuples representing the differences.
  Used internally by `compare/2` to determine if a column needs alteration.

  ## Examples

      changes = PgPushex.Diff.column_changes(current_col, desired_col)
      # Returns: [{:type, :text}, {:null, false}]
  """
  @spec column_changes(Column.t(), Column.t()) :: [column_change()]
  def column_changes(current_column, desired_column) do
    current_type = normalize_type(current_column.type)
    desired_type = normalize_type(desired_column.type)

    []
    |> put_change_if_diff(:type, current_type, desired_type)
    |> put_null_change_if_allowed(current_column, desired_column)
    |> put_change_if_diff(:default, current_column.default, desired_column.default)
    |> put_change_if_diff(:references, current_column.references, desired_column.references)
    |> put_size_change_if_applicable(current_column, desired_column, current_type, desired_type)
    |> put_change_if_diff(:generated_as, current_column.generated_as, desired_column.generated_as)
  end

  @doc false
  defp build_extension_ops(current_extensions, desired_extensions) do
    current_set = MapSet.new(current_extensions)

    desired_extensions
    |> Enum.reject(&MapSet.member?(current_set, &1))
    |> Enum.map(&{:create_extension, &1})
  end

  @doc false
  defp build_enum_ops(current_tables, desired_tables) do
    desired_tables
    |> Enum.flat_map(fn {table_name, desired_table} ->
      current_table = Map.get(current_tables, table_name)

      desired_table.columns
      |> Enum.filter(&(&1.enum != nil))
      |> Enum.filter(fn desired_col ->
        if current_table do
          current_col = Enum.find(current_table.columns, &(&1.name == desired_col.name))
          current_col == nil or current_col.enum == nil
        else
          true
        end
      end)
      |> Enum.map(fn col ->
        {:create_type_enum, "#{table_name}_#{col.name}_enum", col.enum}
      end)
    end)
  end

  @doc false
  defp build_create_table_ops(current_tables, desired_tables) do
    tables_to_create =
      desired_tables
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(current_tables, &1))

    tables_to_create
    |> sort_tables_topologically(desired_tables)
    |> Enum.map(&{:create_table, &1, Map.fetch!(desired_tables, &1)})
  end

  @doc false
  defp build_drop_table_ops(current_tables, desired_tables) do
    tables_to_drop =
      current_tables
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(desired_tables, &1))

    tables_to_drop
    |> sort_tables_topologically(current_tables)
    |> Enum.reverse()
    |> Enum.map(&{:drop_table, &1})
  end

  @doc false
  defp sort_tables_topologically(table_names, all_tables) do
    # Build graph where key is a table name, and value is a list of tables it depends on
    graph =
      Map.new(table_names, fn name ->
        table = Map.fetch!(all_tables, name)

        dependencies =
          table.columns
          |> Enum.map(& &1.references)
          |> Enum.reject(&is_nil/1)
          # Only care about dependencies within the subset
          |> Enum.filter(&(&1 in table_names))
          |> Enum.uniq()

        {name, dependencies}
      end)

    do_topological_sort(graph, [], Map.keys(graph) |> Enum.sort_by(&Atom.to_string/1))
  end

  @doc false
  defp do_topological_sort(graph, sorted, remaining) when map_size(graph) == 0 do
    # All dependencies resolved
    Enum.reverse(sorted) ++ remaining
  end

  @doc false
  defp do_topological_sort(graph, sorted, _remaining) do
    # Find nodes with no dependencies
    no_deps =
      graph
      |> Enum.filter(fn {_node, deps} -> Enum.empty?(deps) end)
      |> Enum.map(fn {node, _deps} -> node end)
      |> Enum.sort_by(&Atom.to_string/1)

    if Enum.empty?(no_deps) do
      # Cycle detected or logic error, fallback to remaining keys
      # This shouldn't happen with well-formed schemas but acts as a safety net
      Enum.reverse(sorted) ++ (Map.keys(graph) |> Enum.sort_by(&Atom.to_string/1))
    else
      # Remove these nodes from graph and from other nodes' dependencies
      new_graph =
        Map.drop(graph, no_deps)
        |> Map.new(fn {node, deps} -> {node, deps -- no_deps} end)

      # Ensure deterministic order by appending sorted `no_deps`
      new_sorted = Enum.reverse(no_deps) ++ sorted

      do_topological_sort(new_graph, new_sorted, [])
    end
  end

  @doc false
  defp compare_table(
         %Table{
           name: table_name,
           columns: current_columns,
           indexes: current_indexes,
           foreign_keys: current_fks
         },
         %Table{columns: desired_columns, indexes: desired_indexes, foreign_keys: desired_fks}
       ) do
    current_columns_by_name = columns_by_name(current_columns)
    desired_columns_by_name = columns_by_name(desired_columns)

    added_columns = added_columns(desired_columns, current_columns_by_name)
    dropped_columns = dropped_columns(current_columns, desired_columns_by_name)

    rename_or_add_drop_ops =
      build_column_presence_ops(table_name, dropped_columns, added_columns)

    alter_ops =
      build_alter_column_ops(
        table_name,
        desired_columns,
        current_columns_by_name,
        current_fks,
        desired_fks
      )

    enum_ops = build_enum_alter_ops(table_name, current_columns_by_name, desired_columns)
    index_ops = build_index_ops(table_name, current_indexes, desired_indexes)

    rename_or_add_drop_ops ++ enum_ops ++ alter_ops ++ index_ops
  end

  @doc false
  defp build_enum_alter_ops(table_name, current_columns_by_name, desired_columns) do
    desired_columns
    |> Enum.filter(&Map.has_key?(current_columns_by_name, &1.name))
    |> Enum.filter(fn desired_col -> desired_col.enum != nil end)
    |> Enum.flat_map(fn desired_col ->
      current_col = Map.fetch!(current_columns_by_name, desired_col.name)

      if current_col.enum != nil do
        added_values = desired_col.enum -- current_col.enum

        if added_values != [] do
          enum_name = "#{table_name}_#{desired_col.name}_enum"
          [{:alter_enum, enum_name, added_values}]
        else
          []
        end
      else
        []
      end
    end)
  end

  @doc false
  defp build_index_ops(table_name, current_indexes, desired_indexes) do
    current_indexes_by_name = indexes_by_name(current_indexes)
    desired_indexes_by_name = indexes_by_name(desired_indexes)

    dropped_indexes =
      current_indexes
      |> Enum.reject(&Map.has_key?(desired_indexes_by_name, &1.name))
      |> Enum.map(&{:drop_index, table_name, &1.name})

    added_indexes =
      desired_indexes
      |> Enum.reject(&Map.has_key?(current_indexes_by_name, &1.name))
      |> Enum.map(&{:create_index, table_name, &1})

    # For existing indexes, if they changed (columns or uniqueness), we drop and recreate them
    modified_indexes =
      desired_indexes
      |> Enum.filter(&Map.has_key?(current_indexes_by_name, &1.name))
      |> Enum.filter(fn desired_index ->
        current_index = Map.fetch!(current_indexes_by_name, desired_index.name)

        current_index.columns != desired_index.columns or
          current_index.unique != desired_index.unique
      end)
      |> Enum.flat_map(fn index ->
        [
          {:drop_index, table_name, index.name},
          {:create_index, table_name, index}
        ]
      end)

    dropped_indexes ++ added_indexes ++ modified_indexes
  end

  @doc false
  defp indexes_by_name(indexes), do: Map.new(indexes, &{&1.name, &1})

  @doc false
  defp build_column_presence_ops(table_name, dropped_columns, added_columns)
       when dropped_columns != [] and added_columns != [] do
    [{:check_column_renames, table_name, dropped_columns, added_columns}]
  end

  @doc false
  defp build_column_presence_ops(table_name, [], added_columns) do
    Enum.map(added_columns, &{:add_column, table_name, &1})
  end

  @doc false
  defp build_column_presence_ops(table_name, dropped_columns, []) do
    Enum.map(dropped_columns, &{:drop_column, table_name, &1.name})
  end

  @doc false
  defp build_alter_column_ops(
         table_name,
         desired_columns,
         current_columns_by_name,
         current_fks,
         desired_fks
       ) do
    desired_columns
    |> Enum.filter(&Map.has_key?(current_columns_by_name, &1.name))
    |> Enum.flat_map(fn desired_column ->
      current_column = Map.fetch!(current_columns_by_name, desired_column.name)
      changes = column_changes(current_column, desired_column)

      # Check if foreign key rules changed for this column
      current_fk = Enum.find(current_fks, &(&1.column_name == desired_column.name))
      desired_fk = Enum.find(desired_fks, &(&1.column_name == desired_column.name))

      changes =
        if current_fk && desired_fk &&
             normalize_fk_action(current_fk.on_delete) !=
               normalize_fk_action(desired_fk.on_delete) do
          changes ++
            [
              {:on_delete, desired_fk.on_delete, desired_fk.referenced_table,
               desired_fk.referenced_column, current_fk.constraint_name}
            ]
        else
          changes
        end

      changes =
        if current_fk && desired_fk &&
             normalize_fk_action(current_fk.on_update) !=
               normalize_fk_action(desired_fk.on_update) do
          changes ++
            [
              {:on_update, desired_fk.on_update, desired_fk.referenced_table,
               desired_fk.referenced_column, current_fk.constraint_name}
            ]
        else
          changes
        end

      # Check if foreign key is being removed
      changes =
        if current_fk && is_nil(desired_fk) && current_fk.constraint_name do
          changes ++ [{:drop_fk, current_fk.constraint_name}]
        else
          changes
        end

      generated_as_change = List.keyfind(changes, :generated_as, 0)

      case generated_as_change do
        {:generated_as, {:fragment, _}} ->
          [{:recreate_generated_column, table_name, desired_column.name, desired_column}]

        _ ->
          case changes do
            [] -> []
            _ -> [{:alter_column, table_name, desired_column.name, changes}]
          end
      end
    end)
  end

  @doc false
  @fk_action_aliases %{delete_all: :cascade, nilify_all: :set_null, update_all: :cascade}

  defp normalize_fk_action(action), do: Map.get(@fk_action_aliases, action, action)

  @type_aliases %{bool: :boolean, int: :integer, binary_id: :binary, text: :string}

  @doc false
  defp normalize_type(type), do: Map.get(@type_aliases, type, type)

  @doc false
  defp put_null_change_if_allowed(changes, current_column, desired_column) do
    if current_column.primary_key or desired_column.primary_key do
      changes
    else
      put_change_if_diff(changes, :null, current_column.null, desired_column.null)
    end
  end

  @doc false
  defp put_size_change_if_applicable(
         changes,
         current_column,
         desired_column,
         current_type,
         desired_type
       ) do
    if current_type == desired_type and current_type in [:string, :vector] do
      case {current_column.size, desired_column.size} do
        {same, same} -> changes
        {_, new_size} -> changes ++ [{:size, new_size, desired_type}]
      end
    else
      changes
    end
  end

  @doc false
  defp put_change_if_diff(changes, key, current_value, desired_value)
       when current_value !== desired_value do
    changes ++ [{key, desired_value}]
  end

  @doc false
  defp put_change_if_diff(changes, _key, _current_value, _desired_value), do: changes

  @doc false
  defp added_columns(desired_columns, current_columns_by_name) do
    Enum.filter(desired_columns, &(not Map.has_key?(current_columns_by_name, &1.name)))
  end

  @doc false
  defp dropped_columns(current_columns, desired_columns_by_name) do
    Enum.filter(current_columns, &(not Map.has_key?(desired_columns_by_name, &1.name)))
  end

  @doc false
  defp columns_by_name(columns), do: Map.new(columns, &{&1.name, &1})

  @doc false
  defp common_table_names(current_tables, desired_tables) do
    current_names = MapSet.new(table_names(current_tables))
    desired_names = MapSet.new(table_names(desired_tables))

    current_names
    |> MapSet.intersection(desired_names)
    |> MapSet.to_list()
    |> sort_names()
  end

  @doc false
  defp table_names(tables) do
    tables
    |> Map.keys()
    |> sort_names()
  end

  @doc false
  defp sort_names(names), do: Enum.sort_by(names, &Atom.to_string/1)
end
