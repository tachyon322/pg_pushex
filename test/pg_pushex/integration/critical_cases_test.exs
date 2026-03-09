defmodule PgPushex.Integration.CriticalCasesTest do
  use PgPushex.Integration.TestCase, async: false

  @moduletag :integration

  describe "adding NOT NULL column without default to non-empty table" do
    test "fails when adding NOT NULL column to table with existing rows" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY);")
      execute_sql("INSERT INTO users (id) VALUES (DEFAULT);")

      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:email, :string, null: false)
          ])
        ])

      assert_raise Postgrex.Error, ~r/contains null values/, fn ->
        push_schema!(desired)
      end
    end

    test "succeeds when adding NOT NULL column with default to table with existing rows" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY);")
      execute_sql("INSERT INTO users (id) VALUES (DEFAULT);")

      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:email, :string, null: false, default: "test@example.com")
          ])
        ])

      push_schema!(desired)

      result = execute_sql("SELECT email FROM users;")
      assert result.rows == [["test@example.com"]]
    end

    test "succeeds when adding nullable column without default" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY);")
      execute_sql("INSERT INTO users (id) VALUES (DEFAULT);")

      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:email, :string, null: true)
          ])
        ])

      push_schema!(desired)

      result = execute_sql("SELECT email FROM users;")
      assert result.rows == [[nil]]
    end
  end

  describe "creating UNIQUE index on column with duplicates" do
    test "fails when creating unique index on column with duplicate values" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, email text);")
      execute_sql("INSERT INTO users (email) VALUES ('a@test.com'), ('a@test.com');")

      desired =
        build_schema([
          build_table(
            :users,
            [
              build_column(:id, :serial, primary_key: true),
              build_column(:email, :string)
            ],
            indexes: [
              %Index{name: :users_email_index, columns: [:email], unique: true}
            ]
          )
        ])

      assert_raise Postgrex.Error, ~r/duplicate key value violates unique constraint/, fn ->
        push_schema!(desired)
      end
    end

    test "succeeds when creating unique index on column with unique values" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, email text);")
      execute_sql("INSERT INTO users (email) VALUES ('a@test.com'), ('b@test.com');")

      desired =
        build_schema([
          build_table(
            :users,
            [
              build_column(:id, :serial, primary_key: true),
              build_column(:email, :string)
            ],
            indexes: [
              %Index{name: :users_email_index, columns: [:email], unique: true}
            ]
          )
        ])

      push_schema!(desired)

      result =
        execute_sql(
          "SELECT indexname FROM pg_indexes WHERE tablename = 'users' AND indexname = 'users_email_index';"
        )

      assert result.rows == [["users_email_index"]]
    end
  end

  describe "type conversion with USING clause" do
    test "converts integer to string correctly" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, code integer);")
      execute_sql("INSERT INTO items (code) VALUES (123), (456);")

      desired =
        build_schema([
          build_table(:items, [
            build_column(:id, :serial, primary_key: true),
            build_column(:code, :string)
          ])
        ])

      push_schema!(desired)

      result = execute_sql("SELECT code FROM items ORDER BY id;")
      assert result.rows == [["123"], ["456"]]
    end

    test "converts string to integer when values are numeric strings" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, code text);")
      execute_sql("INSERT INTO items (code) VALUES ('123'), ('456');")

      desired =
        build_schema([
          build_table(:items, [
            build_column(:id, :serial, primary_key: true),
            build_column(:code, :integer)
          ])
        ])

      push_schema!(desired)

      result = execute_sql("SELECT code FROM items ORDER BY id;")
      assert result.rows == [[123], [456]]
    end

    test "fails when converting non-numeric string to integer" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, code text);")
      execute_sql("INSERT INTO items (code) VALUES ('abc');")

      desired =
        build_schema([
          build_table(:items, [
            build_column(:id, :serial, primary_key: true),
            build_column(:code, :integer)
          ])
        ])

      assert_raise Postgrex.Error, ~r/invalid input syntax for type integer/, fn ->
        push_schema!(desired)
      end
    end
  end

  describe "changing column nullability" do
    test "fails when setting NOT NULL on column with NULL values" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, email text);")
      execute_sql("INSERT INTO users (email) VALUES (NULL);")

      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:email, :string, null: false)
          ])
        ])

      assert_raise Postgrex.Error, ~r/contains null values/, fn ->
        push_schema!(desired)
      end
    end

    test "succeeds when setting NOT NULL on column without NULL values" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, email text NOT NULL);")
      execute_sql("INSERT INTO users (email) VALUES ('test@example.com');")

      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:email, :string, null: false)
          ])
        ])

      push_schema!(desired)

      current = introspect_schema()
      email_col = Enum.find(current.tables[:users].columns, &(&1.name == :email))
      assert email_col.null == false
    end

    test "succeeds when changing NOT NULL to nullable" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, email text NOT NULL);")
      execute_sql("INSERT INTO users (email) VALUES ('test@example.com');")

      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:email, :string, null: true)
          ])
        ])

      push_schema!(desired)

      current = introspect_schema()
      email_col = Enum.find(current.tables[:users].columns, &(&1.name == :email))
      assert email_col.null == true
    end
  end

  describe "changing column default" do
    test "sets default on column without default" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, status text);")

      desired =
        build_schema([
          build_table(:items, [
            build_column(:id, :serial, primary_key: true),
            build_column(:status, :string, default: "active")
          ])
        ])

      push_schema!(desired)

      execute_sql("INSERT INTO items DEFAULT VALUES;")
      result = execute_sql("SELECT status FROM items WHERE id = (SELECT MAX(id) FROM items);")
      assert result.rows == [["active"]]
    end

    test "changes existing default" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, status text DEFAULT 'pending');")

      desired =
        build_schema([
          build_table(:items, [
            build_column(:id, :serial, primary_key: true),
            build_column(:status, :string, default: "active")
          ])
        ])

      push_schema!(desired)

      execute_sql("INSERT INTO items DEFAULT VALUES;")
      result = execute_sql("SELECT status FROM items WHERE id = (SELECT MAX(id) FROM items);")
      assert result.rows == [["active"]]
    end

    test "removes default" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, status text DEFAULT 'pending');")

      desired =
        build_schema([
          build_table(:items, [
            build_column(:id, :serial, primary_key: true),
            build_column(:status, :string)
          ])
        ])

      push_schema!(desired)

      execute_sql("INSERT INTO items DEFAULT VALUES;")
      result = execute_sql("SELECT status FROM items WHERE id = (SELECT MAX(id) FROM items);")
      assert result.rows == [[nil]]
    end
  end

  describe "dropping column that has data" do
    test "permanently deletes column data" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, name text, email text);")
      execute_sql("INSERT INTO users (name, email) VALUES ('John', 'john@test.com');")

      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:email, :string)
          ])
        ])

      push_schema!(desired)

      assert_raise Postgrex.Error, ~r/column "name" of relation "users" does not exist/, fn ->
        execute_sql("SELECT name FROM users;")
      end

      result = execute_sql("SELECT email FROM users;")
      assert result.rows == [["john@test.com"]]
    end
  end

  describe "dropping table" do
    test "permanently deletes table and all data" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, name text);")
      execute_sql("INSERT INTO users (name) VALUES ('John');")
      execute_sql("CREATE TABLE posts (id serial PRIMARY KEY, title text);")

      desired =
        build_schema([
          build_table(:posts, [
            build_column(:id, :serial, primary_key: true),
            build_column(:title, :string)
          ])
        ])

      push_schema!(desired)

      assert_raise Postgrex.Error, ~r/relation "users" does not exist/, fn ->
        execute_sql("SELECT * FROM users;")
      end

      result = execute_sql("SELECT COUNT(*) FROM posts;")
      assert result.rows == [[0]]
    end
  end

  describe "table with reserved word name" do
    test "creates table with reserved word name" do
      desired =
        build_schema([
          build_table(:order, [
            build_column(:id, :serial, primary_key: true),
            build_column(:total, :integer)
          ])
        ])

      push_schema!(desired)

      result = execute_sql("SELECT COUNT(*) FROM \"order\";")
      assert result.rows == [[0]]
    end

    test "creates column with reserved word name" do
      desired =
        build_schema([
          build_table(:items, [
            build_column(:id, :serial, primary_key: true),
            build_column(:limit, :integer)
          ])
        ])

      push_schema!(desired)

      result = execute_sql("SELECT \"limit\" FROM items;")
      assert result.rows == []
    end
  end

  describe "changing string column size" do
    test "reduces varchar size" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, name varchar(100));")
      execute_sql("INSERT INTO users (name) VALUES ('John');")

      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:name, :string, size: 50)
          ])
        ])

      push_schema!(desired)

      result = execute_sql("SELECT name FROM users;")
      assert result.rows == [["John"]]
    end

    test "increases varchar size" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, name varchar(10));")

      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:name, :string, size: 100)
          ])
        ])

      push_schema!(desired)

      result =
        execute_sql(
          "SELECT character_maximum_length FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'name';"
        )

      assert result.rows == [[100]]
    end

    test "changes varchar to text (removes size limit)" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, name varchar(100));")

      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:name, :string)
          ])
        ])

      push_schema!(desired)

      result =
        execute_sql(
          "SELECT character_maximum_length FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'name';"
        )

      assert result.rows == [[nil]]
    end
  end

  describe "complex default values with fragments" do
    test "sets UUID default with gen_random_uuid" do
      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :uuid,
              primary_key: true,
              default: {:fragment, "gen_random_uuid()"}
            ),
            build_column(:name, :string)
          ])
        ])

      push_schema!(desired)

      execute_sql("INSERT INTO users (name) VALUES ('Test');")
      result = execute_sql("SELECT id FROM users WHERE name = 'Test';")
      assert [[uuid]] = result.rows

      assert String.match?(
               uuid,
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
             )
    end

    test "sets timestamp default with now()" do
      desired =
        build_schema([
          build_table(:events, [
            build_column(:id, :serial, primary_key: true),
            build_column(:created_at, :utc_datetime, default: {:fragment, "now()"})
          ])
        ])

      push_schema!(desired)

      execute_sql("INSERT INTO events DEFAULT VALUES;")
      result = execute_sql("SELECT created_at IS NOT NULL FROM events;")
      assert result.rows == [[true]]
    end
  end
end
