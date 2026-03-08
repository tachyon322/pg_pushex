defmodule ExDrizzle.State.ForeignKey do
  @enforce_keys [:column_name, :referenced_table, :referenced_column, :on_delete]
  defstruct column_name: nil, referenced_table: nil, referenced_column: nil, on_delete: :nothing

  @type column_name :: atom()
  @type table_name :: atom()
  @type referenced_column_name :: atom()
  @type on_delete_action :: :nothing | :cascade | :restrict | :set_null

  @type t :: %__MODULE__{
          column_name: column_name(),
          referenced_table: table_name(),
          referenced_column: referenced_column_name(),
          on_delete: on_delete_action()
        }
end
