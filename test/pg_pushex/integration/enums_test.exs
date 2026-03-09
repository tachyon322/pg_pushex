defmodule PgPushex.Integration.EnumsTest do
  use PgPushex.Integration.TestCase, async: false

  @moduletag :integration

  describe "creating table with enum column" do
    test "creates enum type and table with enum column" do
      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:status, :string, enum: ["active", "inactive", "pending"])
          ])
        ])

      push_schema!(desired)

      result = execute_sql("SELECT typname FROM pg_type WHERE typname = 'users_status_enum';")
      assert result.rows == [["users_status_enum"]]
    end

    test "inserts valid enum values" do
      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:status, :string, enum: ["active", "inactive"])
          ])
        ])

      push_schema!(desired)

      execute_sql("INSERT INTO users (status) VALUES ('active');")

      result = execute_sql("SELECT status FROM users;")
      assert result.rows == [["active"]]
    end

    test "fails when inserting invalid enum value" do
      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:status, :string, enum: ["active", "inactive"])
          ])
        ])

      push_schema!(desired)

      assert_raise Postgrex.Error, ~r/invalid input value for enum/, fn ->
        execute_sql("INSERT INTO users (status) VALUES ('unknown');")
      end
    end
  end

  describe "adding enum column to existing table" do
    test "creates enum type and adds column" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY);")

      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:role, :string, enum: ["admin", "user", "guest"])
          ])
        ])

      push_schema!(desired)

      result = execute_sql("SELECT typname FROM pg_type WHERE typname = 'users_role_enum';")
      assert result.rows == [["users_role_enum"]]
    end
  end

  describe "adding new values to existing enum" do
    test "adds new enum value to existing type" do
      execute_sql("CREATE TYPE users_status_enum AS ENUM ('active', 'inactive');")
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, status users_status_enum);")

      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:status, :string, enum: ["active", "inactive", "pending"])
          ])
        ])

      push_schema!(desired)

      execute_sql("INSERT INTO users (status) VALUES ('pending');")

      result = execute_sql("SELECT status FROM users;")
      assert result.rows == [["pending"]]
    end

    test "adds multiple new enum values" do
      execute_sql("CREATE TYPE users_status_enum AS ENUM ('active');")
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, status users_status_enum);")

      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:status, :string, enum: ["active", "inactive", "pending", "banned"])
          ])
        ])

      push_schema!(desired)

      execute_sql("INSERT INTO users (status) VALUES ('banned');")

      result = execute_sql("SELECT status FROM users;")
      assert result.rows == [["banned"]]
    end
  end

  describe "multiple tables with different enums" do
    test "creates separate enum types for different tables" do
      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:status, :string, enum: ["active", "inactive"])
          ]),
          build_table(:orders, [
            build_column(:id, :serial, primary_key: true),
            build_column(:status, :string, enum: ["pending", "completed", "cancelled"])
          ])
        ])

      push_schema!(desired)

      result = execute_sql("SELECT COUNT(*) FROM pg_type WHERE typname LIKE '%_status_enum';")
      assert result.rows == [[2]]
    end

    test "each enum type is independent" do
      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:status, :string, enum: ["active"])
          ]),
          build_table(:orders, [
            build_column(:id, :serial, primary_key: true),
            build_column(:status, :string, enum: ["active", "shipped"])
          ])
        ])

      push_schema!(desired)

      execute_sql("INSERT INTO orders (status) VALUES ('shipped');")

      result = execute_sql("SELECT status FROM orders;")
      assert result.rows == [["shipped"]]
    end
  end

  describe "enum with default value" do
    test "creates enum column with default" do
      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:status, :string, enum: ["active", "inactive"], default: "active")
          ])
        ])

      push_schema!(desired)

      execute_sql("INSERT INTO users DEFAULT VALUES;")

      result = execute_sql("SELECT status FROM users;")
      assert result.rows == [["active"]]
    end
  end

  describe "enum with NOT NULL constraint" do
    test "creates NOT NULL enum column" do
      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:status, :string, enum: ["active", "inactive"], null: false)
          ])
        ])

      push_schema!(desired)

      assert_raise Postgrex.Error,
                   ~r/null value in column "status" violates not-null constraint/,
                   fn ->
                     execute_sql("INSERT INTO users DEFAULT VALUES;")
                   end
    end
  end

  describe "introspecting enum columns" do
    test "correctly reads enum values" do
      execute_sql("CREATE TYPE users_status_enum AS ENUM ('active', 'inactive', 'pending');")
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, status users_status_enum);")

      schema = introspect_schema()

      users_table = schema.tables[:users]
      status_col = Enum.find(users_table.columns, &(&1.name == :status))

      assert status_col != nil
      assert status_col.enum == ["active", "inactive", "pending"]
    end
  end

  describe "changing from enum to regular string" do
    test "detects change from enum to non-enum" do
      execute_sql("CREATE TYPE users_status_enum AS ENUM ('active', 'inactive');")
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, status users_status_enum);")

      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:status, :string)
          ])
        ])

      current = introspect_schema()
      operations = Diff.compare(current, desired)

      assert Enum.any?(operations, fn
               {:alter_column, :users, :status, [type: :string]} -> true
               _ -> false
             end)
    end
  end

  describe "changing from regular string to enum" do
    test "creates enum type and changes column type" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, status text);")
      execute_sql("INSERT INTO users (status) VALUES ('active');")

      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:status, :string, enum: ["active", "inactive"])
          ])
        ])

      push_schema!(desired)

      result = execute_sql("SELECT status FROM users;")
      assert result.rows == [["active"]]
    end
  end

  describe "enum idempotency" do
    test "does not recreate existing enum type" do
      execute_sql("CREATE TYPE users_status_enum AS ENUM ('active', 'inactive');")
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, status users_status_enum);")

      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true),
            build_column(:status, :string, enum: ["active", "inactive"])
          ])
        ])

      current = introspect_schema()
      operations = Diff.compare(current, desired)

      assert operations == []
    end
  end
end
