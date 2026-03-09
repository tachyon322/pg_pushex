defmodule PgPushex.State.Table do
  @moduledoc """
  Represents a database table definition.

  Stores the table name along with all its columns, indexes,
  and foreign key constraints.
  """

  alias PgPushex.State.{Column, ForeignKey, Index}

  @enforce_keys [:name]
  defstruct name: nil, columns: [], foreign_keys: [], indexes: []

  @typedoc "Table name as an atom."
  @type name :: atom()

  @typedoc "List of column definitions."
  @type columns :: [Column.t()]

  @typedoc "List of foreign key constraints."
  @type foreign_keys :: [ForeignKey.t()]

  @typedoc "List of index definitions."
  @type indexes :: [Index.t()]

  @typedoc "Table struct type."
  @type t :: %__MODULE__{
          name: name(),
          columns: columns(),
          foreign_keys: foreign_keys(),
          indexes: indexes()
        }
end
