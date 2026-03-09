defmodule PgPushex.Integration.GeneratedColumnsTest do
  use PgPushex.Integration.TestCase, async: false

  @moduletag :integration

  describe "creating table with generated column" do
    test "creates table with simple generated column" do
      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:first_name, :string),
            build_column(:last_name, :string),
            build_column(:full_name, :string,
              generated_as: {:fragment, "first_name || ' ' || last_name"}
            )
          ])
        ])

      push_schema!(desired)

      execute_sql("INSERT INTO users (first_name, last_name) VALUES ('John', 'Doe');")

      result = execute_sql("SELECT full_name FROM users;")
      assert result.rows == [["John Doe"]]
    end

    test "creates generated column with computed value" do
      desired =
        build_schema([
          build_table(:products, [
            build_column(:id, :serial, primary_key: true),
            build_column(:price, :integer),
            build_column(:tax, :integer),
            build_column(:total, :integer, generated_as: {:fragment, "price + tax"})
          ])
        ])

      push_schema!(desired)

      execute_sql("INSERT INTO products (price, tax) VALUES (100, 20);")

      result = execute_sql("SELECT total FROM products;")
      assert result.rows == [[120]]
    end
  end

  describe "adding generated column to existing table" do
    test "adds generated column to existing table" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, first_name text, last_name text);")
      execute_sql("INSERT INTO users (first_name, last_name) VALUES ('Jane', 'Smith');")

      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:first_name, :string),
            build_column(:last_name, :string),
            build_column(:full_name, :string,
              generated_as: {:fragment, "first_name || ' ' || last_name"}
            )
          ])
        ])

      push_schema!(desired)

      result = execute_sql("SELECT full_name FROM users;")
      assert result.rows == [["Jane Smith"]]
    end
  end

  describe "changing generated expression" do
    test "detects change in generated expression" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, first_name text, last_name text);")
      execute_sql("INSERT INTO users (first_name, last_name) VALUES ('John', 'Doe');")

      execute_sql(
        "ALTER TABLE users ADD COLUMN full_name text GENERATED ALWAYS AS (first_name || ' ' || last_name) STORED;"
      )

      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:first_name, :string),
            build_column(:last_name, :string),
            build_column(:full_name, :string,
              generated_as: {:fragment, "upper(first_name) || ' ' || upper(last_name)"}
            )
          ])
        ])

      current = introspect_schema()
      operations = Diff.compare(current, desired)

      assert Enum.any?(operations, fn
               {:recreate_generated_column, :users, :full_name, _} -> true
               _ -> false
             end)
    end
  end

  describe "removing generated column" do
    test "drops generated column" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, first_name text);")

      execute_sql(
        "ALTER TABLE users ADD COLUMN upper_name text GENERATED ALWAYS AS (upper(first_name)) STORED;"
      )

      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:first_name, :string)
          ])
        ])

      push_schema!(desired)

      assert_raise Postgrex.Error,
                   ~r/column "upper_name" of relation "users" does not exist/,
                   fn ->
                     execute_sql("SELECT upper_name FROM users;")
                   end
    end
  end

  describe "generated column constraints" do
    test "cannot set default on generated column" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, quantity integer);")

      desired =
        build_schema([
          build_table(:items, [
            build_column(:id, :serial, primary_key: true),
            build_column(:quantity, :integer),
            build_column(:double_quantity, :integer,
              generated_as: {:fragment, "quantity * 2"},
              default: 0
            )
          ])
        ])

      current = introspect_schema()
      operations = Diff.compare(current, desired)

      assert Enum.any?(operations, fn
               {:add_column, :items, %Column{name: :double_quantity}} -> true
               _ -> false
             end)
    end
  end

  describe "introspecting generated columns" do
    test "correctly reads generated expression" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, first_name text, last_name text);")

      execute_sql(
        "ALTER TABLE users ADD COLUMN full_name text GENERATED ALWAYS AS (first_name || ' ' || last_name) STORED;"
      )

      schema = introspect_schema()

      users_table = schema.tables[:users]
      full_name_col = Enum.find(users_table.columns, &(&1.name == :full_name))

      assert full_name_col != nil
      assert full_name_col.generated_as != nil

      case full_name_col.generated_as do
        {:fragment, expr} -> assert expr =~ "first_name"
        _ -> flunk("Expected generated_as to be a fragment")
      end
    end
  end

  describe "generated column with different types" do
    test "creates integer generated column" do
      desired =
        build_schema([
          build_table(:orders, [
            build_column(:id, :serial, primary_key: true),
            build_column(:price, :integer),
            build_column(:quantity, :integer),
            build_column(:total, :integer, generated_as: {:fragment, "price * quantity"})
          ])
        ])

      push_schema!(desired)

      execute_sql("INSERT INTO orders (price, quantity) VALUES (10, 5);")

      result = execute_sql("SELECT total FROM orders;")
      assert result.rows == [[50]]
    end

    test "creates boolean generated column" do
      desired =
        build_schema([
          build_table(:items, [
            build_column(:id, :serial, primary_key: true),
            build_column(:stock, :integer),
            build_column(:in_stock, :boolean, generated_as: {:fragment, "stock > 0"})
          ])
        ])

      push_schema!(desired)

      execute_sql("INSERT INTO items (stock) VALUES (10), (0), (5);")

      result = execute_sql("SELECT in_stock FROM items ORDER BY id;")
      assert result.rows == [[true], [false], [true]]
    end
  end

  describe "generated column cannot be updated directly" do
    test "insert works but direct update on generated column fails" do
      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:name, :string),
            build_column(:upper_name, :string, generated_as: {:fragment, "upper(name)"})
          ])
        ])

      push_schema!(desired)

      execute_sql("INSERT INTO users (name) VALUES ('john');")

      assert_raise Postgrex.Error, ~r/generated_always/, fn ->
        execute_sql("UPDATE users SET upper_name = 'MANUAL';")
      end
    end
  end
end
