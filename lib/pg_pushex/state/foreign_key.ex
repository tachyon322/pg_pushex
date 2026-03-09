defmodule PgPushex.State.ForeignKey do
  @moduledoc """
  Represents a foreign key constraint.

  Defines the relationship between a column in one table
  and a column in another (referenced) table.
  """

  @enforce_keys [:column_name, :referenced_table, :referenced_column, :on_delete, :on_update]
  defstruct column_name: nil,
            referenced_table: nil,
            referenced_column: nil,
            on_delete: :nothing,
            on_update: :nothing

  @typedoc "Name of the column that has the foreign key constraint."
  @type column_name :: atom()

  @typedoc "Name of the referenced table."
  @type table_name :: atom()

  @typedoc "Name of the referenced column (usually :id)."
  @type referenced_column_name :: atom()

  @typedoc "ON DELETE action for the foreign key."
  @type on_delete_action ::
          :nothing | :cascade | :restrict | :set_null | :delete_all | :nilify_all

  @typedoc "ON UPDATE action for the foreign key."
  @type on_update_action ::
          :nothing | :cascade | :restrict | :set_null | :update_all | :nilify_all

  @typedoc "Foreign key struct type."
  @type t :: %__MODULE__{
          column_name: column_name(),
          referenced_table: table_name(),
          referenced_column: referenced_column_name(),
          on_delete: on_delete_action(),
          on_update: on_update_action()
        }
end
