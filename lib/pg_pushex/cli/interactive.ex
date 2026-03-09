defmodule PgPushex.CLI.Interactive do
  @moduledoc """
  Interactive resolver for ambiguous schema changes.

  When the diff algorithm detects that columns have been dropped and added
  in the same table, it could indicate either:
  1. A column was renamed (data should be preserved)
  2. Columns were dropped and new ones added (data loss acceptable)

  This module interactively prompts the user to resolve these ambiguities
  and also confirms destructive operations like dropping tables.
  """

  alias PgPushex.State.Column

  @typedoc """
  A diff operation that may require user confirmation.

  See `PgPushex.Diff.operation/0` for the full list.
  """
  @type operation :: PgPushex.Diff.operation()

  @doc """
  Resolves potential column renames through interactive prompts.

  Iterates through operations and prompts the user when rename
  candidates are detected. Returns modified operations with renames
  resolved or `:abort` if the user cancels.

  ## Parameters

  - `operations` - List of diff operations from `PgPushex.Diff.compare/2`

  ## Returns

  - `{:ok, resolved_operations}` - Operations with renames resolved
  - `:abort` - User chose to abort the migration
  """
  @spec resolve_renames([operation()]) :: {:ok, [operation()]} | :abort
  def resolve_renames(operations) do
    resolve_all(operations, [])
  end

  @doc false
  defp resolve_all([], acc), do: {:ok, Enum.reverse(acc)}

  @doc false
  defp resolve_all([{:check_column_renames, table, dropped_columns, added_columns} | rest], acc) do
    case resolve_check(table, dropped_columns, added_columns) do
      {:ok, resolved_ops} -> resolve_all(rest, Enum.reverse(resolved_ops) ++ acc)
      :abort -> :abort
    end
  end

  @doc false
  defp resolve_all([{:drop_table, table} = op | rest], acc) do
    case confirm_drop_table(table) do
      :ok -> resolve_all(rest, [op | acc])
      :abort -> :abort
    end
  end

  @doc false
  defp resolve_all(
         [{:recreate_generated_column, table, col_name, desired_col} | rest],
         acc
       ) do
    case confirm_recreate_generated(table, col_name) do
      :ok ->
        ops = [
          {:drop_column, table, col_name},
          {:add_column, table, desired_col}
        ]

        resolve_all(rest, Enum.reverse(ops) ++ acc)

      :abort ->
        :abort
    end
  end

  @doc false
  defp resolve_all([op | rest], acc) do
    resolve_all(rest, [op | acc])
  end

  @doc false
  defp resolve_check(table, dropped_columns, added_columns) do
    IO.puts("")
    IO.puts(IO.ANSI.format([:yellow, "Column changes detected in table :#{table}"]))
    IO.puts("")

    Enum.each(dropped_columns, fn %Column{name: name, type: type} ->
      IO.puts("  Dropped: #{name} (#{type})")
    end)

    Enum.each(added_columns, fn %Column{name: name, type: type} ->
      IO.puts("  Added:   #{name} (#{type})")
    end)

    IO.puts("")

    options =
      [
        {"Drop old columns and create new ones (DATA LOSS)", :drop_and_add}
        | Enum.map(dropped_columns, fn dropped ->
            Enum.map(added_columns, fn added ->
              {"Rename #{dropped.name} to #{added.name}", {:rename, dropped, added}}
            end)
          end)
          |> List.flatten()
      ]

    choice = present_menu("How would you like to proceed?", options ++ [{"Abort", :abort}])

    case choice do
      :abort ->
        :abort

      :drop_and_add ->
        drop_ops = Enum.map(dropped_columns, &{:drop_column, table, &1.name})
        add_ops = Enum.map(added_columns, &{:add_column, table, &1})
        {:ok, drop_ops ++ add_ops}

      {:rename, dropped, added} ->
        rename_op = {:rename_column, table, dropped.name, added.name}

        remaining_dropped = Enum.reject(dropped_columns, &(&1.name == dropped.name))
        remaining_added = Enum.reject(added_columns, &(&1.name == added.name))

        other_ops =
          Enum.map(remaining_dropped, &{:drop_column, table, &1.name}) ++
            Enum.map(remaining_added, &{:add_column, table, &1})

        {:ok, [rename_op | other_ops]}
    end
  end

  @doc false
  defp confirm_drop_table(table) do
    IO.puts("")

    message =
      IO.ANSI.format([
        :red,
        "Warning: ",
        :reset,
        "About to drop table ",
        :bright,
        ":#{table}",
        :reset,
        ". All data in this table will be lost."
      ])

    IO.puts(message)

    if Mix.shell().yes?("Proceed with dropping table?") do
      :ok
    else
      :abort
    end
  end

  @doc false
  defp confirm_recreate_generated(table, col_name) do
    IO.puts("")

    message =
      IO.ANSI.format([
        :yellow,
        "Warning: ",
        :reset,
        "Need to recreate generated column ",
        :bright,
        "#{col_name}",
        :reset,
        " in table ",
        :bright,
        ":#{table}",
        :reset,
        "."
      ])

    IO.puts(message)
    IO.puts("This will drop and re-add the column.")

    if Mix.shell().yes?("Proceed with recreating the generated column?") do
      :ok
    else
      :abort
    end
  end

  @doc false
  defp present_menu(prompt, options) do
    IO.puts(prompt)
    IO.puts("")

    options
    |> Enum.with_index(1)
    |> Enum.each(fn {{label, _value}, index} ->
      IO.puts("  #{index}. #{label}")
    end)

    IO.puts("")
    input = Mix.shell().prompt("Enter choice: ") |> String.trim()

    case Integer.parse(input) do
      {n, ""} when n > 0 and n <= length(options) ->
        {_, value} = Enum.at(options, n - 1)
        value

      _ ->
        IO.puts("Invalid choice. Please enter a number.")
        present_menu(prompt, options)
    end
  end
end
