defmodule PgPushex.State.Schema do
  @moduledoc """
  Represents the complete database schema.

  Contains all tables, raw SQL statements to execute, and PostgreSQL
  extensions required by the schema.
  """

  alias PgPushex.State.Table

  defstruct tables: %{}, raw_sqls: [], extensions: []

  @typedoc "Table name as an atom."
  @type table_name :: atom()

  @typedoc "Map of table names to Table structs."
  @type tables :: %{optional(table_name()) => Table.t()}

  @typedoc "Schema struct type."
  @type t :: %__MODULE__{
          tables: tables(),
          raw_sqls: [String.t()],
          extensions: [String.t()]
        }

  @doc """
  Creates a new empty schema.

  ## Returns

  An empty `%PgPushex.State.Schema{}` struct.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Adds a table to the schema.

  ## Parameters

  - `schema` - The schema struct to add to
  - `table` - The Table struct to add

  ## Returns

  Updated schema struct with the table added.
  """
  @spec add_table(t(), Table.t()) :: t()
  def add_table(%__MODULE__{} = schema, %Table{} = table) do
    %__MODULE__{schema | tables: Map.put(schema.tables, table.name, table)}
  end
end
