defmodule PgPushex.SchemaTest do
  use ExUnit.Case, async: true

  alias PgPushex.State.{Column, Schema, Table}

  describe "DSL schema compilation" do
    test "builds schema via __schema__/0 and preserves column order" do
      module =
        compile_schema_module!("""
        table :users do
          column :id, :uuid, primary_key: true, null: false
          column :email, :string, null: false
          column :age, :integer, default: 18
        end
        """)

      schema = module.__schema__()

      assert %Schema{} = schema

      assert %Table{name: :users} = users_table = schema.tables[:users]

      assert users_table.columns == [
               %Column{name: :id, type: :uuid, null: false, default: nil, primary_key: true},
               %Column{
                 name: :email,
                 type: :string,
                 null: false,
                 default: nil,
                 primary_key: false
               },
               %Column{name: :age, type: :integer, null: true, default: 18, primary_key: false}
             ]
    end

    test "forces null: false when primary_key: true even if null is not specified" do
      module =
        compile_schema_module!("""
        table :items do
          column :id, :uuid, primary_key: true
        end
        """)

      schema = module.__schema__()
      id_column = hd(schema.tables[:items].columns)

      assert id_column.primary_key == true
      assert id_column.null == false
    end

    test "forces null: false when primary_key: true even if null: true is explicit" do
      module =
        compile_schema_module!("""
        table :items do
          column :id, :uuid, primary_key: true, null: true
        end
        """)

      schema = module.__schema__()
      id_column = hd(schema.tables[:items].columns)

      assert id_column.primary_key == true
      assert id_column.null == false
    end

    test "preserves fragment defaults in the compiled schema" do
      module =
        compile_schema_module!("""
        table :users do
          column :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
        end
        """)

      schema = module.__schema__()
      id_column = hd(schema.tables[:users].columns)

      assert id_column.default == {:fragment, "gen_random_uuid()"}
    end

    test "raises on unknown column option" do
      assert_raise ArgumentError, ~r/unknown column options/, fn ->
        compile_schema_module!("""
        table :users do
          column :id, :uuid, primry_key: true
        end
        """)
      end
    end

    test "raises on duplicate columns inside one table" do
      assert_raise ArgumentError, ~r/duplicate column names/, fn ->
        compile_schema_module!("""
        table :users do
          column :email, :string
          column :email, :string
        end
        """)
      end
    end

    test "raises on duplicate table names" do
      assert_raise ArgumentError, ~r/duplicate table name/, fn ->
        compile_schema_module!("""
        table :users do
          column :id, :uuid
        end

        table :users do
          column :email, :string
        end
        """)
      end
    end

    test "raises when column is declared outside table" do
      assert_raise ArgumentError, ~r/column\/3 must be declared inside table\/2/, fn ->
        compile_schema_module!("""
        column :id, :uuid
        """)
      end
    end
  end

  defp compile_schema_module!(schema_body) do
    module_name = unique_module_name()

    code =
      """
      defmodule #{inspect(module_name)} do
        use PgPushex.Schema

      #{schema_body}
      end
      """

    [{^module_name, _bytecode}] = Code.compile_string(code)

    module_name
  end

  defp unique_module_name do
    unique_suffix = System.unique_integer([:positive])
    Module.concat([__MODULE__, Dynamic, String.to_atom("Schema#{unique_suffix}")])
  end
end
