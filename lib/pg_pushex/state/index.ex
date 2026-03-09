defmodule PgPushex.State.Index do
  @moduledoc """
  Represents a database index definition.

  Can represent both regular and unique indexes on one or more columns.
  """

  @enforce_keys [:name, :columns]
  defstruct name: nil, columns: [], unique: false

  @typedoc "Index name as an atom or string."
  @type name :: atom() | String.t()

  @typedoc "List of column names (as atoms) included in the index."
  @type columns :: [atom()]

  @typedoc "Whether this is a unique index."
  @type unique_flag :: boolean()

  @typedoc "Index struct type."
  @type t :: %__MODULE__{
          name: name(),
          columns: columns(),
          unique: unique_flag()
        }
end
