defmodule ExDrizzle.State.Column do
  @enforce_keys [:name, :type]
  defstruct name: nil, type: nil, null: true, default: nil, primary_key: false

  @type name :: atom()
  @type data_type :: atom()
  @type nullability :: boolean()
  @type default_value :: term()
  @type primary_key_flag :: boolean()

  @type t :: %__MODULE__{
          name: name(),
          type: data_type(),
          null: nullability(),
          default: default_value(),
          primary_key: primary_key_flag()
        }
end
