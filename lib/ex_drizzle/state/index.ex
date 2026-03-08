defmodule ExDrizzle.State.Index do
  @enforce_keys [:name, :columns]
  defstruct name: nil, columns: [], unique: false

  @type name :: atom() | String.t()
  @type columns :: [atom()]
  @type unique_flag :: boolean()

  @type t :: %__MODULE__{
          name: name(),
          columns: columns(),
          unique: unique_flag()
        }
end
