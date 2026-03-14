defmodule PgPushex.State.Column do
  @moduledoc """
  Represents a column definition in a database table.

  This struct stores all properties of a database column including
  its name, data type, constraints, defaults, and relationships.
  """

  @enforce_keys [:name, :type]
  defstruct name: nil,
            type: nil,
            null: true,
            default: nil,
            primary_key: false,
            references: nil,
            referenced_column: nil,
            constraint_name: nil,
            enum: nil,
            size: nil,
            precision: nil,
            scale: nil,
            generated_as: nil,
            on_delete: :nothing,
            on_update: :nothing

  @typedoc "Column name as an atom."
  @type name :: atom()

  @typedoc "Column data type (e.g., `:string`, `:integer`, `:uuid`)."
  @type data_type :: atom()

  @typedoc "Whether the column allows NULL values."
  @type nullability :: boolean()

  @typedoc "Default value for the column, can be a literal or `{:fragment, sql}`."
  @type default_value :: term()

  @typedoc "Whether this column is part of the primary key."
  @type primary_key_flag :: boolean()

  @typedoc "Referenced table name for foreign keys, or nil."
  @type references_table :: atom() | nil

  @typedoc "Referenced column name for foreign keys, defaults to :id."
  @type referenced_column_name :: atom() | nil

  @typedoc "Name of the foreign key constraint in PostgreSQL, or nil."
  @type constraint_name :: String.t() | nil

  @typedoc "List of enum values for enum columns, or nil."
  @type enum_values :: [String.t()] | nil

  @typedoc "Size constraint (e.g., varchar length), or nil."
  @type size_val :: integer() | nil

  @typedoc "Precision for numeric/decimal columns, or nil."
  @type precision_val :: integer() | nil

  @typedoc "Scale for numeric/decimal columns, or nil."
  @type scale_val :: integer() | nil

  @typedoc "Generated column expression as `{:fragment, sql}`, or nil."
  @type generated_as_val :: nil | {:fragment, String.t()}

  @typedoc """
  Foreign key action for ON DELETE or ON UPDATE.

  Supported actions:
  - `:nothing` - No action (default)
  - `:cascade` - Cascade the operation
  - `:restrict` - Prevent the operation
  - `:set_null` - Set referencing column to NULL
  - `:delete_all` - Delete referencing rows (alias for cascade)
  - `:nilify_all` - Set to NULL (alias for set_null)
  - `:update_all` - Update referencing rows (for ON UPDATE)
  """
  @type fk_action ::
          :nothing | :cascade | :restrict | :set_null | :delete_all | :nilify_all | :update_all

  @typedoc "Column struct type."
  @type t :: %__MODULE__{
          name: name(),
          type: data_type(),
          null: nullability(),
          default: default_value(),
          primary_key: primary_key_flag(),
          references: references_table(),
          referenced_column: referenced_column_name(),
          constraint_name: constraint_name(),
          enum: enum_values(),
          size: size_val(),
          precision: precision_val(),
          scale: scale_val(),
          generated_as: generated_as_val(),
          on_delete: fk_action(),
          on_update: fk_action()
        }
end
