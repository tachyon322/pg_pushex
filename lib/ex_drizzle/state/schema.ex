defmodule ExDrizzle.State.Schema do
  alias ExDrizzle.State.Table

  defstruct tables: %{}

  @type table_name :: atom()
  @type tables :: %{optional(table_name()) => Table.t()}

  @type t :: %__MODULE__{
          tables: tables()
        }

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec add_table(t(), Table.t()) :: t()
  def add_table(%__MODULE__{} = schema, %Table{} = table) do
    %__MODULE__{schema | tables: Map.put(schema.tables, table.name, table)}
  end
end
