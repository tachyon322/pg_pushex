defmodule PgPushex.Schema do
  @moduledoc """
  Provides the DSL for defining database schemas declaratively.

  This module is imported when you `use PgPushex.Schema` and provides
  macros for defining tables, columns, indexes, and other database objects.

  ## Example

      defmodule MyApp.Schema do
        use PgPushex.Schema

        extension "uuid-ossp"

        table :users do
          column :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
          column :email, :string, size: 255, null: false
          column :is_active, :boolean, default: true

          timestamps(type: :utc_datetime)

          index :users_email_index, [:email], unique: true
        end
      end

  ## Column Types

  The following types are supported:

  - `:string` - VARCHAR with optional size
  - `:text` - TEXT
  - `:integer`, `:int` - INTEGER
  - `:bigint` - BIGINT
  - `:serial` - SERIAL (auto-increment)
  - `:bigserial` - BIGSERIAL
  - `:smallint` - SMALLINT
  - `:uuid` - UUID
  - `:boolean`, `:bool` - BOOLEAN
  - `:float` - DOUBLE PRECISION
  - `:decimal` - NUMERIC
  - `:date` - DATE
  - `:time` - TIME
  - `:naive_datetime` - TIMESTAMP WITHOUT TIME ZONE
  - `:utc_datetime` - TIMESTAMP WITH TIME ZONE
  - `:binary`, `:binary_id` - BYTEA
  - `:map` - JSONB
  - `:vector` - VECTOR (requires pgvector extension)
  - `:tsvector` - TSVECTOR (for full-text search)
  - `:citext` - CITEXT (case-insensitive text, requires extension)

  ## Column Options

  - `:null` - Boolean, defaults to `true` (except primary keys)
  - `:default` - Default value or `fragment("SQL")`
  - `:primary_key` - Boolean, marks column as primary key
  - `:references` - Atom referencing another table
  - `:on_delete` - Action for foreign key: `:nothing`, `:delete_all`, `:nilify_all`, `:restrict`
  - `:on_update` - Action for foreign key: `:nothing`, `:update_all`, `:nilify_all`, `:restrict`
  - `:size` - Size for string types (e.g., `size: 255`)
  - `:enum` - List of strings for enum values
  - `:generated_as` - Generated column expression via `fragment/1`
  """

  alias PgPushex.State.{Column, Schema, Table}

  @allowed_column_opts [
    :null,
    :default,
    :primary_key,
    :references,
    :enum,
    :size,
    :on_delete,
    :on_update,
    :generated_as
  ]
  @valid_types [
    :string,
    :text,
    :integer,
    :uuid,
    :boolean,
    :serial,
    :int,
    :bool,
    :float,
    :decimal,
    :date,
    :time,
    :naive_datetime,
    :utc_datetime,
    :binary,
    :binary_id,
    :map,
    :vector,
    :bigint,
    :bigserial,
    :smallint,
    :tsvector,
    :citext
  ]

  # Map from column type to required PostgreSQL extension name
  @type_to_extension %{
    vector: "vector",
    citext: "citext"
  }

  @doc """
  Imports the schema DSL macros into the calling module.

  This macro sets up the necessary module attributes and imports
  all schema definition macros: `table/2`, `column/2`, `column/3`,
  `index/2`, `index/3`, `unique_index/2`, `fragment/1`, `timestamps/0`,
  `timestamps/1`, `execute/1`, and `extension/1`.
  """
  defmacro __using__(_opts) do
    quote do
      import PgPushex.Schema,
        only: [
          table: 2,
          column: 2,
          column: 3,
          index: 2,
          index: 3,
          unique_index: 2,
          fragment: 1,
          timestamps: 0,
          timestamps: 1,
          execute: 1,
          extension: 1
        ]

      Module.register_attribute(__MODULE__, :pg_pushex_tables, accumulate: true)
      Module.register_attribute(__MODULE__, :pg_pushex_raw_sqls, accumulate: true)
      Module.register_attribute(__MODULE__, :pg_pushex_extensions, accumulate: true)
      Module.register_attribute(__MODULE__, :pg_pushex_current_columns, accumulate: true)
      Module.register_attribute(__MODULE__, :pg_pushex_current_indexes, accumulate: true)
      Module.register_attribute(__MODULE__, :pg_pushex_current_foreign_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :pg_pushex_current_table, persist: false)

      @before_compile PgPushex.Schema
    end
  end

  @doc """
  Creates a raw SQL fragment for use in column defaults or generated columns.

  ## Examples

      column :id, :uuid, default: fragment("gen_random_uuid()")
      column :full_name, :string, generated_as: fragment("first_name || ' ' || last_name")
  """
  defmacro fragment(sql) do
    quote do
      {:fragment, unquote(sql)}
    end
  end

  @doc """
  Executes raw SQL during schema push.

  **Important:** The SQL statement will be executed on every `mix pg_pushex.push`,
  even if the database is already in sync. Ensure your SQL is idempotent
  (safe to run multiple times) or include your own conditional logic.

  ## Example

      execute "CREATE EXTENSION IF NOT EXISTS \\\"uuid-ossp\\\""
  """
  defmacro execute(sql) do
    quote do
      sql_value = unquote(sql)

      unless is_binary(sql_value) do
        raise ArgumentError,
              "execute/1 expects a string, got: #{inspect(sql_value)}"
      end

      Module.put_attribute(__MODULE__, :pg_pushex_raw_sqls, sql_value)
    end
  end

  @doc """
  Declares a PostgreSQL extension required by this schema.

  The extension will be created with `CREATE EXTENSION IF NOT EXISTS` before
  any tables are created or modified. Extensions for types `:vector` and `:citext`
  are also inferred automatically from column types — you only need to call
  `extension/1` explicitly for other extensions (e.g. `"uuid-ossp"`).

  ## Example

      extension "uuid-ossp"
      extension "vector"
  """
  defmacro extension(name) do
    quote do
      ext_value = unquote(name)

      unless is_binary(ext_value) do
        raise ArgumentError,
              "extension/1 expects a string, got: #{inspect(ext_value)}"
      end

      Module.put_attribute(__MODULE__, :pg_pushex_extensions, ext_value)
    end
  end

  @doc """
  Defines a database table with columns and indexes.

  ## Options

  - `:primary_key` - Boolean, creates an implicit `id` column (default: true)

  ## Examples

      table :users do
        column :id, :uuid, primary_key: true
        column :email, :string, null: false
        timestamps()
      end

      table :posts, primary_key: false do
        column :id, :serial, primary_key: true
        column :title, :string
      end
  """
  defmacro table(name, do: block) do
    quote do
      table_name = unquote(name)

      PgPushex.Schema.__assert_atom!(table_name, :table_name)
      PgPushex.Schema.__assert_not_nested_table!(__MODULE__, table_name)

      Module.delete_attribute(__MODULE__, :pg_pushex_current_columns)
      Module.put_attribute(__MODULE__, :pg_pushex_current_table, table_name)

      unquote(block)

      columns =
        __MODULE__
        |> Module.get_attribute(:pg_pushex_current_columns)
        |> List.wrap()
        |> Enum.reverse()

      indexes =
        __MODULE__
        |> Module.get_attribute(:pg_pushex_current_indexes)
        |> List.wrap()
        |> Enum.reverse()

      foreign_keys =
        __MODULE__
        |> Module.get_attribute(:pg_pushex_current_foreign_keys)
        |> List.wrap()
        |> Enum.reverse()

      PgPushex.Schema.__assert_unique_columns!(__MODULE__, table_name, columns)
      PgPushex.Schema.__assert_unique_indexes!(__MODULE__, table_name, indexes)

      table = %PgPushex.State.Table{
        name: table_name,
        columns: columns,
        indexes: indexes,
        foreign_keys: foreign_keys
      }

      PgPushex.Schema.__put_table!(__MODULE__, table)

      Module.delete_attribute(__MODULE__, :pg_pushex_current_columns)
      Module.delete_attribute(__MODULE__, :pg_pushex_current_indexes)
      Module.delete_attribute(__MODULE__, :pg_pushex_current_foreign_keys)
      Module.delete_attribute(__MODULE__, :pg_pushex_current_table)

      :ok
    end
  end

  @doc """
  Defines a column within a table.

  ## Options

  - `:null` - Whether the column allows NULL values (default: `true`, `false` for primary keys)
  - `:default` - Default value, can be a literal or `fragment("SQL expression")`
  - `:primary_key` - Whether this column is the primary key (default: `false`)
  - `:references` - Table atom to create a foreign key constraint
  - `:on_delete` - Foreign key action on delete: `:nothing`, `:delete_all`, `:nilify_all`, `:restrict`
  - `:on_update` - Foreign key action on update: `:nothing`, `:update_all`, `:nilify_all`, `:restrict`
  - `:size` - Size constraint for string types (e.g., `size: 255`)
  - `:enum` - List of strings for PostgreSQL ENUM type (e.g., `enum: ["active", "inactive"]`)
  - `:generated_as` - SQL expression for generated column via `fragment/1`

  ## Examples

      column :email, :string, size: 255, null: false
      column :status, :string, enum: ["draft", "published", "archived"], default: "draft"
      column :user_id, :uuid, references: :users, on_delete: :delete_all
      column :full_name, :string, generated_as: fragment("first_name || ' ' || last_name")
      column :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
  """
  defmacro column(name, type, opts \\ []) do
    quote do
      current_table = Module.get_attribute(__MODULE__, :pg_pushex_current_table)

      PgPushex.Schema.__assert_column_context!(__MODULE__, current_table)

      column_name = unquote(name)
      column_type = unquote(type)
      column_opts = unquote(opts)

      PgPushex.Schema.__assert_atom!(column_name, :column_name)
      PgPushex.Schema.__assert_atom!(column_type, :column_type)
      PgPushex.Schema.__validate_column_type!(column_type, current_table, column_name)

      PgPushex.Schema.__validate_column_opts!(
        column_opts,
        __MODULE__,
        current_table,
        column_name
      )

      is_pk = Keyword.get(column_opts, :primary_key, false)
      references = Keyword.get(column_opts, :references, nil)
      enum_values = Keyword.get(column_opts, :enum, nil)
      generated_as = Keyword.get(column_opts, :generated_as, nil)

      if generated_as != nil and Keyword.has_key?(column_opts, :default) do
        raise ArgumentError,
              ":generated_as and :default are mutually exclusive for #{inspect(__MODULE__)}.#{inspect(current_table)}.#{inspect(column_name)}"
      end

      if generated_as != nil do
        case generated_as do
          {:fragment, sql} when is_binary(sql) ->
            :ok

          _ ->
            raise ArgumentError,
                  ":generated_as must be a fragment(...) for #{inspect(__MODULE__)}.#{inspect(current_table)}.#{inspect(column_name)}, got: #{inspect(generated_as)}"
        end
      end

      if references != nil do
        PgPushex.Schema.__assert_atom!(references, :references)
      end

      if enum_values != nil and not is_list(enum_values) do
        raise ArgumentError,
              ":enum option must be a list of strings for #{inspect(__MODULE__)}.#{inspect(current_table)}.#{inspect(column_name)}, got: #{inspect(enum_values)}"
      end

      on_delete =
        if(references != nil, do: Keyword.get(column_opts, :on_delete, :nothing), else: :nothing)

      on_update =
        if(references != nil, do: Keyword.get(column_opts, :on_update, :nothing), else: :nothing)

      column = %PgPushex.State.Column{
        name: column_name,
        type: column_type,
        null: if(is_pk, do: false, else: Keyword.get(column_opts, :null, true)),
        default: Keyword.get(column_opts, :default, nil),
        primary_key: is_pk,
        references: references,
        enum: enum_values,
        size: Keyword.get(column_opts, :size, nil),
        generated_as: generated_as,
        on_delete: on_delete,
        on_update: on_update
      }

      if references != nil do
        on_delete = Keyword.get(column_opts, :on_delete, :nothing)
        on_update = Keyword.get(column_opts, :on_update, :nothing)

        unless on_delete in [:nothing, :delete_all, :nilify_all, :restrict] do
          raise ArgumentError,
                ":on_delete option must be one of [:nothing, :delete_all, :nilify_all, :restrict] for #{inspect(__MODULE__)}.#{inspect(current_table)}.#{inspect(column_name)}, got: #{inspect(on_delete)}"
        end

        unless on_update in [:nothing, :update_all, :nilify_all, :restrict] do
          raise ArgumentError,
                ":on_update option must be one of [:nothing, :update_all, :nilify_all, :restrict] for #{inspect(__MODULE__)}.#{inspect(current_table)}.#{inspect(column_name)}, got: #{inspect(on_update)}"
        end

        fk = %PgPushex.State.ForeignKey{
          column_name: column_name,
          referenced_table: references,
          referenced_column: :id,
          on_delete: on_delete,
          on_update: on_update
        }

        Module.put_attribute(__MODULE__, :pg_pushex_current_foreign_keys, fk)
      end

      Module.put_attribute(__MODULE__, :pg_pushex_current_columns, column)

      :ok
    end
  end

  @doc """
  Adds automatic timestamp columns to the table.

  Creates `inserted_at` and `updated_at` columns with the specified type.
  Both columns are non-nullable and have no default value.

  ## Options

  - `:type` - The datetime type: `:utc_datetime` (default), `:naive_datetime`, etc.
  - `:inserted_at` - Whether to add the inserted_at column (default: `true`)
  - `:updated_at` - Whether to add the updated_at column (default: `true`)

  ## Examples

      timestamps()
      timestamps(type: :naive_datetime)
      timestamps(inserted_at: false, updated_at: true)
  """
  defmacro timestamps(opts \\ []) do
    quote do
      current_table = Module.get_attribute(__MODULE__, :pg_pushex_current_table)

      PgPushex.Schema.__assert_column_context!(__MODULE__, current_table)

      type = Keyword.get(unquote(opts), :type, :utc_datetime)
      inserted_at = Keyword.get(unquote(opts), :inserted_at, true)
      updated_at = Keyword.get(unquote(opts), :updated_at, true)

      if inserted_at do
        col_inserted = %PgPushex.State.Column{
          name: :inserted_at,
          type: type,
          null: false,
          default: nil,
          primary_key: false,
          references: nil,
          enum: nil,
          size: nil,
          generated_as: nil,
          on_delete: :nothing,
          on_update: :nothing
        }

        Module.put_attribute(__MODULE__, :pg_pushex_current_columns, col_inserted)
      end

      if updated_at do
        col_updated = %PgPushex.State.Column{
          name: :updated_at,
          type: type,
          null: false,
          default: nil,
          primary_key: false,
          references: nil,
          enum: nil,
          size: nil,
          generated_as: nil,
          on_delete: :nothing,
          on_update: :nothing
        }

        Module.put_attribute(__MODULE__, :pg_pushex_current_columns, col_updated)
      end

      :ok
    end
  end

  @doc """
  Defines a unique index on the current table.

  A convenience macro equivalent to `index(name, columns, unique: true)`.

  ## Examples

      unique_index :users_email_unique, [:email]
      unique_index :posts_slug_unique, [:slug]
  """
  defmacro unique_index(name, columns) do
    quote do
      PgPushex.Schema.index(unquote(name), unquote(columns), unique: true)
    end
  end

  @doc """
  Defines an index on the current table.

  ## Options

  - `:unique` - Whether this is a unique index (default: `false`)

  ## Examples

      index :users_email_index, [:email]
      index :posts_author_id_index, [:author_id]
      index :users_name_index, [:first_name, :last_name], unique: true
  """
  defmacro index(name, columns, opts \\ []) do
    quote do
      current_table = Module.get_attribute(__MODULE__, :pg_pushex_current_table)

      PgPushex.Schema.__assert_index_context!(__MODULE__, current_table)

      index_name = unquote(name)
      index_columns = unquote(columns)
      index_opts = unquote(opts)

      PgPushex.Schema.__assert_atom!(index_name, :index_name)

      unless is_list(index_columns) and Enum.all?(index_columns, &is_atom/1) do
        raise ArgumentError,
              "index columns must be a list of atoms for #{inspect(__MODULE__)}.#{inspect(current_table)}.#{inspect(index_name)}, got: #{inspect(index_columns)}"
      end

      unique = Keyword.get(index_opts, :unique, false)

      unless is_boolean(unique) do
        raise ArgumentError,
              ":unique option must be boolean for #{inspect(__MODULE__)}.#{inspect(current_table)}.#{inspect(index_name)}, got: #{inspect(unique)}"
      end

      index = %PgPushex.State.Index{
        name: index_name,
        columns: index_columns,
        unique: unique
      }

      Module.put_attribute(__MODULE__, :pg_pushex_current_indexes, index)

      :ok
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    tables =
      env.module
      |> Module.get_attribute(:pg_pushex_tables)
      |> List.wrap()
      |> Enum.reverse()

    raw_sqls =
      env.module
      |> Module.get_attribute(:pg_pushex_raw_sqls)
      |> List.wrap()
      |> Enum.reverse()

    explicit_extensions =
      env.module
      |> Module.get_attribute(:pg_pushex_extensions)
      |> List.wrap()
      |> Enum.reverse()

    # Infer extensions from column types
    inferred_extensions =
      tables
      |> Enum.flat_map(& &1.columns)
      |> Enum.map(& &1.type)
      |> Enum.flat_map(fn type ->
        case Map.get(@type_to_extension, type) do
          nil -> []
          ext -> [ext]
        end
      end)

    extensions =
      (explicit_extensions ++ inferred_extensions)
      |> Enum.uniq()

    schema = %Schema{
      tables: Map.new(tables, &{&1.name, &1}),
      raw_sqls: raw_sqls,
      extensions: extensions
    }

    quote do
      @spec __schema__() :: PgPushex.State.Schema.t()
      def __schema__, do: unquote(Macro.escape(schema))
    end
  end

  @doc false
  @spec __assert_atom!(term(), atom()) :: :ok
  def __assert_atom!(value, _label) when is_atom(value), do: :ok

  def __assert_atom!(value, label) do
    raise ArgumentError, "#{label} must be an atom, got: #{inspect(value)}"
  end

  @doc false
  @spec __assert_not_nested_table!(module(), atom()) :: :ok
  def __assert_not_nested_table!(module, new_table_name) do
    case Module.get_attribute(module, :pg_pushex_current_table) do
      nil ->
        :ok

      current_table_name ->
        raise ArgumentError,
              "nested table declarations are not supported in #{inspect(module)}: current=#{inspect(current_table_name)} new=#{inspect(new_table_name)}"
    end
  end

  @doc false
  @spec __assert_column_context!(module(), atom() | nil) :: :ok
  def __assert_column_context!(_module, current_table)
      when is_atom(current_table) and not is_nil(current_table),
      do: :ok

  def __assert_column_context!(module, _current_table) do
    raise ArgumentError, "column/3 must be declared inside table/2 in #{inspect(module)}"
  end

  @doc false
  @spec __assert_index_context!(module(), atom() | nil) :: :ok
  def __assert_index_context!(_module, current_table)
      when is_atom(current_table) and not is_nil(current_table),
      do: :ok

  def __assert_index_context!(module, _current_table) do
    raise ArgumentError,
          "index/2 or index/3 must be declared inside table/2 in #{inspect(module)}"
  end

  @doc false
  @spec __validate_column_type!(atom(), atom(), atom()) :: :ok
  def __validate_column_type!(type, table_name, column_name) do
    if type in @valid_types do
      :ok
    else
      suggestion = suggest_type(type)

      hint =
        if suggestion,
          do: "\nDid you mean #{inspect(suggestion)}?\n",
          else: "\n"

      supported = @valid_types |> Enum.map(&inspect/1) |> Enum.join(", ")

      raise CompileError,
        description:
          "Invalid type #{inspect(type)} used for column #{column_name} in table #{table_name}." <>
            hint <>
            "Supported types are: #{supported}."
    end
  end

  defp suggest_type(invalid_type) do
    invalid_str = Atom.to_string(invalid_type)

    {best_match, best_score} =
      Enum.reduce(@valid_types, {nil, 0.0}, fn valid_type, {match, score} ->
        jaro = String.jaro_distance(invalid_str, Atom.to_string(valid_type))
        if jaro > score, do: {valid_type, jaro}, else: {match, score}
      end)

    if best_score >= 0.8, do: best_match, else: nil
  end

  @doc false
  @spec __validate_column_opts!(term(), module(), atom(), atom()) :: :ok
  def __validate_column_opts!(opts, module, table_name, column_name) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError,
            "column options must be a keyword list for #{inspect(module)}.#{inspect(table_name)}.#{inspect(column_name)}, got: #{inspect(opts)}"
    end

    unknown_opts = Keyword.keys(opts) -- @allowed_column_opts

    if unknown_opts != [] do
      raise ArgumentError,
            "unknown column options for #{inspect(module)}.#{inspect(table_name)}.#{inspect(column_name)}: #{inspect(unknown_opts)}"
    end

    null = Keyword.get(opts, :null, true)
    primary_key = Keyword.get(opts, :primary_key, false)

    unless is_boolean(null) do
      raise ArgumentError,
            ":null option must be boolean for #{inspect(module)}.#{inspect(table_name)}.#{inspect(column_name)}, got: #{inspect(null)}"
    end

    unless is_boolean(primary_key) do
      raise ArgumentError,
            ":primary_key option must be boolean for #{inspect(module)}.#{inspect(table_name)}.#{inspect(column_name)}, got: #{inspect(primary_key)}"
    end

    :ok
  end

  @doc false
  @spec __assert_unique_columns!(module(), atom(), [Column.t()]) :: :ok
  def __assert_unique_columns!(module, table_name, columns) do
    duplicate_names =
      columns
      |> Enum.map(& &1.name)
      |> Enum.group_by(& &1)
      |> Enum.filter(fn {_name, grouped_names} -> length(grouped_names) > 1 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort_by(&Atom.to_string/1)

    if duplicate_names != [] do
      raise ArgumentError,
            "duplicate column names in #{inspect(module)}.#{inspect(table_name)}: #{inspect(duplicate_names)}"
    end

    :ok
  end

  @doc false
  @spec __assert_unique_indexes!(module(), atom(), [PgPushex.State.Index.t()]) :: :ok
  def __assert_unique_indexes!(module, table_name, indexes) do
    duplicate_names =
      indexes
      |> Enum.map(& &1.name)
      |> Enum.group_by(& &1)
      |> Enum.filter(fn {_name, grouped_names} -> length(grouped_names) > 1 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort_by(&Atom.to_string/1)

    if duplicate_names != [] do
      raise ArgumentError,
            "duplicate index names in #{inspect(module)}.#{inspect(table_name)}: #{inspect(duplicate_names)}"
    end

    :ok
  end

  @doc false
  @spec __put_table!(module(), Table.t()) :: :ok
  def __put_table!(module, %Table{name: table_name} = table) do
    existing_tables =
      module
      |> Module.get_attribute(:pg_pushex_tables)
      |> List.wrap()

    if Enum.any?(existing_tables, &(&1.name == table_name)) do
      raise ArgumentError,
            "duplicate table name in #{inspect(module)}: #{inspect(table_name)}"
    end

    Module.put_attribute(module, :pg_pushex_tables, table)

    :ok
  end
end
