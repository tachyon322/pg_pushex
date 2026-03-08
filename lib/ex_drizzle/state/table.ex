defmodule ExDrizzle.State.Table do
  alias ExDrizzle.State.{Column, ForeignKey, Index}

  @enforce_keys [:name]
  defstruct name: nil, columns: [], foreign_keys: [], indexes: []

  @type name :: atom()
  @type columns :: [Column.t()]
  @type foreign_keys :: [ForeignKey.t()]
  @type indexes :: [Index.t()]

  @type t :: %__MODULE__{
          name: name(),
          columns: columns(),
          foreign_keys: foreign_keys(),
          indexes: indexes()
        }
end
