defmodule PgPushex.SQL.PostgresTest do
  use ExUnit.Case, async: true

  alias PgPushex.State.{Column, ForeignKey, Index, Table}
  alias PgPushex.SQL.Postgres

  describe "generate/1" do
    test "generates create table SQL" do
      table =
        %Table{
          name: :users,
          columns: [
            %Column{name: :id, type: :uuid, null: false, primary_key: true},
            %Column{name: :name, type: :string, null: false, default: "john"},
            %Column{name: :active, type: :boolean, default: true}
          ]
        }

      assert Postgres.generate([{:create_table, :users, table}]) ==
               [
                 ~s|CREATE TABLE "users" ("id" uuid NOT NULL, "name" text NOT NULL DEFAULT 'john', "active" boolean DEFAULT TRUE, PRIMARY KEY ("id"));|
               ]
    end

    test "generates drop table SQL" do
      assert Postgres.generate([{:drop_table, :users}]) == [~s|DROP TABLE "users";|]
    end

    test "generates add column SQL" do
      column = %Column{name: :email, type: :string, null: false, default: "a@b.com"}

      assert Postgres.generate([{:add_column, :users, column}]) ==
               [~s|ALTER TABLE "users" ADD COLUMN "email" text NOT NULL DEFAULT 'a@b.com';|]
    end

    test "generates drop column SQL" do
      assert Postgres.generate([{:drop_column, :users, :email}]) ==
               [~s|ALTER TABLE "users" DROP COLUMN "email";|]
    end

    test "generates rename column SQL" do
      assert Postgres.generate([{:rename_column, :users, :name, :first_name}]) ==
               [~s|ALTER TABLE "users" RENAME COLUMN "name" TO "first_name";|]
    end

    test "generates alter column SQL for type/null/default changes" do
      operation =
        {:alter_column, :users, :external_id,
         [
           type: :uuid,
           null: false,
           default: "abc-123"
         ]}

      assert Postgres.generate([operation]) ==
               [
                 ~s|ALTER TABLE "users" ALTER COLUMN "external_id" TYPE uuid USING "external_id"::uuid;|,
                 ~s|ALTER TABLE "users" ALTER COLUMN "external_id" SET NOT NULL;|,
                 ~s|ALTER TABLE "users" ALTER COLUMN "external_id" SET DEFAULT 'abc-123';|
               ]
    end

    test "generates alter column SQL for size changes" do
      assert Postgres.generate([{:alter_column, :users, :title, [{:size, 100, :string}]}]) ==
               [
                 ~s|ALTER TABLE "users" ALTER COLUMN "title" TYPE varchar(100);|
               ]

      assert Postgres.generate([{:alter_column, :users, :title, [{:size, nil, :string}]}]) ==
               [
                 ~s|ALTER TABLE "users" ALTER COLUMN "title" TYPE text;|
               ]
    end

    test "generates drop default SQL when default is nil in alter column" do
      operation = {:alter_column, :users, :name, [default: nil]}

      assert Postgres.generate([operation]) ==
               [~s|ALTER TABLE "users" ALTER COLUMN "name" DROP DEFAULT;|]
    end

    test "renders fragment defaults without quoting" do
      table =
        %Table{
          name: :users,
          columns: [
            %Column{name: :id, type: :uuid, null: false, primary_key: true},
            %Column{name: :inserted_at, type: :string, default: {:fragment, "now()"}}
          ]
        }

      assert Postgres.generate([{:create_table, :users, table}]) ==
               [
                 ~s|CREATE TABLE "users" ("id" uuid NOT NULL, "inserted_at" text DEFAULT now(), PRIMARY KEY ("id"));|
               ]
    end

    test "raises on unsupported operation" do
      assert_raise ArgumentError, ~r/unsupported operation/, fn ->
        Postgres.generate([{:check_column_renames, :users, [], []}])
      end
    end
  end

  describe "dangerous operations" do
    test "raises when trying to change type to serial" do
      assert_raise ArgumentError,
                   ~r/Cannot change the type of an existing column to :serial/,
                   fn ->
                     Postgres.generate([{:alter_column, :users, :id, [type: :serial]}])
                   end
    end

    test "raises when trying to alter generated expression in place" do
      assert_raise ArgumentError, ~r/Cannot alter generated expression/, fn ->
        Postgres.generate([
          {:alter_column, :users, :computed, [generated_as: {:fragment, "new_expr"}]}
        ])
      end
    end
  end

  describe "foreign key SQL generation" do
    test "generates CREATE TABLE with FK and on_delete cascade" do
      table = %Table{
        name: :comments,
        columns: [
          %Column{name: :id, type: :serial, primary_key: true},
          %Column{name: :post_id, type: :integer, references: :posts, on_delete: :cascade}
        ],
        foreign_keys: [
          %ForeignKey{
            column_name: :post_id,
            referenced_table: :posts,
            referenced_column: :id,
            on_delete: :cascade,
            on_update: :nothing
          }
        ]
      }

      [sql] = Postgres.generate([{:create_table, :comments, table}])

      assert sql =~ ~s|REFERENCES "posts"(id) ON DELETE CASCADE|
    end

    test "generates CREATE TABLE with FK and on_delete set_null" do
      table = %Table{
        name: :comments,
        columns: [
          %Column{name: :id, type: :serial, primary_key: true},
          %Column{name: :post_id, type: :integer, references: :posts, on_delete: :set_null}
        ],
        foreign_keys: [
          %ForeignKey{
            column_name: :post_id,
            referenced_table: :posts,
            referenced_column: :id,
            on_delete: :set_null,
            on_update: :nothing
          }
        ]
      }

      [sql] = Postgres.generate([{:create_table, :comments, table}])

      assert sql =~ ~s|ON DELETE SET NULL|
    end

    test "generates CREATE TABLE with FK and on_update cascade" do
      table = %Table{
        name: :comments,
        columns: [
          %Column{name: :id, type: :serial, primary_key: true},
          %Column{name: :post_id, type: :integer, references: :posts, on_update: :cascade}
        ],
        foreign_keys: [
          %ForeignKey{
            column_name: :post_id,
            referenced_table: :posts,
            referenced_column: :id,
            on_delete: :nothing,
            on_update: :cascade
          }
        ]
      }

      [sql] = Postgres.generate([{:create_table, :comments, table}])

      assert sql =~ ~s|ON UPDATE CASCADE|
    end

    test "generates ADD COLUMN with FK" do
      column = %Column{name: :post_id, type: :integer, references: :posts, on_delete: :cascade}

      table = %Table{
        name: :comments,
        columns: [column],
        foreign_keys: [
          %ForeignKey{
            column_name: :post_id,
            referenced_table: :posts,
            referenced_column: :id,
            on_delete: :cascade,
            on_update: :nothing
          }
        ]
      }

      [sql] = Postgres.generate([{:add_column, :comments, column}])

      assert sql =~ ~s|REFERENCES "posts"(id) ON DELETE CASCADE|
    end

    test "generates alter_column with on_delete change (comment only)" do
      [sql] =
        Postgres.generate([
          {:alter_column, :comments, :post_id, [{:on_delete, :restrict, :posts}]}
        ])

      assert sql =~ ~s|-- Note:|
      assert sql =~ ~s|ADD FOREIGN KEY|
    end
  end

  describe "generated columns SQL" do
    test "generates CREATE TABLE with generated column" do
      table = %Table{
        name: :users,
        columns: [
          %Column{name: :id, type: :serial, primary_key: true},
          %Column{name: :first_name, type: :string},
          %Column{
            name: :full_name,
            type: :string,
            generated_as: {:fragment, "first_name || ' ' || last_name"}
          }
        ]
      }

      [sql] = Postgres.generate([{:create_table, :users, table}])

      assert sql =~ "GENERATED ALWAYS AS (first_name || ' ' || last_name) STORED"
    end

    test "generates ADD COLUMN with generated column" do
      column = %Column{name: :upper_name, type: :string, generated_as: {:fragment, "upper(name)"}}

      [sql] = Postgres.generate([{:add_column, :users, column}])

      assert sql =~ ~S|GENERATED ALWAYS AS (upper(name)) STORED|
    end

    test "generates recreate_generated_column as DROP + ADD" do
      column = %Column{name: :upper_name, type: :string, generated_as: {:fragment, "lower(name)"}}

      [drop_sql, add_sql] =
        Postgres.generate([{:recreate_generated_column, :users, :upper_name, column}])

      assert drop_sql == ~s|ALTER TABLE "users" DROP COLUMN "upper_name";|
      assert add_sql =~ ~s|ADD COLUMN "upper_name"|
      assert add_sql =~ ~S|GENERATED ALWAYS AS (lower(name)) STORED|
    end
  end

  describe "index SQL generation" do
    test "generates CREATE INDEX" do
      index = %Index{name: :users_email_index, columns: [:email], unique: false}

      [sql] = Postgres.generate([{:create_index, :users, index}])

      assert sql == ~s|CREATE INDEX "users_email_index" ON "users" ("email");|
    end

    test "generates CREATE UNIQUE INDEX" do
      index = %Index{name: :users_email_unique, columns: [:email], unique: true}

      [sql] = Postgres.generate([{:create_index, :users, index}])

      assert sql == ~s|CREATE UNIQUE INDEX "users_email_unique" ON "users" ("email");|
    end

    test "generates multi-column index" do
      index = %Index{name: :users_name_index, columns: [:first_name, :last_name], unique: false}

      [sql] = Postgres.generate([{:create_index, :users, index}])

      assert sql == ~s|CREATE INDEX "users_name_index" ON "users" ("first_name", "last_name");|
    end

    test "generates DROP INDEX" do
      [sql] = Postgres.generate([{:drop_index, :users, :users_email_index}])

      assert sql == ~s|DROP INDEX "users_email_index";|
    end
  end

  describe "enum SQL generation" do
    test "generates CREATE TYPE for enum" do
      [sql] =
        Postgres.generate([{:create_type_enum, "users_status_enum", ["active", "inactive"]}])

      assert sql =~ ~s|CREATE TYPE "users_status_enum" AS ENUM|
      assert sql =~ ~s|'active'|
      assert sql =~ ~s|'inactive'|
    end

    test "generates idempotent CREATE TYPE (handles duplicate)" do
      [sql] = Postgres.generate([{:create_type_enum, "users_status_enum", ["active"]}])

      assert sql =~ ~s|EXCEPTION WHEN duplicate_object THEN null|
    end

    test "generates ALTER TYPE for adding enum values" do
      sqls = Postgres.generate([{:alter_enum, "users_status_enum", ["pending", "banned"]}])

      assert length(sqls) == 2

      assert Enum.at(sqls, 0) =~
               ~s|ALTER TYPE "users_status_enum" ADD VALUE IF NOT EXISTS 'pending'|

      assert Enum.at(sqls, 1) =~
               ~s|ALTER TYPE "users_status_enum" ADD VALUE IF NOT EXISTS 'banned'|
    end
  end

  describe "quoting identifiers" do
    test "properly quotes reserved words as table names" do
      table = %Table{
        name: :order,
        columns: [%Column{name: :id, type: :serial, primary_key: true}]
      }

      [sql] = Postgres.generate([{:create_table, :order, table}])

      assert sql =~ ~s|CREATE TABLE "order"|
    end

    test "properly quotes reserved words as column names" do
      table = %Table{
        name: :items,
        columns: [
          %Column{name: :id, type: :serial, primary_key: true},
          %Column{name: :limit, type: :integer}
        ]
      }

      [sql] = Postgres.generate([{:create_table, :items, table}])

      assert sql =~ ~s|"limit" integer|
    end
  end

  describe "type conversions" do
    test "generates USING clause for type changes" do
      [sql] = Postgres.generate([{:alter_column, :items, :code, [type: :string]}])

      assert sql =~ ~s|TYPE text USING "code"::text|
    end

    test "generates correct SQL for integer type" do
      [sql] = Postgres.generate([{:alter_column, :items, :count, [type: :integer]}])

      assert sql =~ ~s|TYPE integer|
    end

    test "generates correct SQL for uuid type" do
      [sql] = Postgres.generate([{:alter_column, :items, :external_id, [type: :uuid]}])

      assert sql =~ ~s|TYPE uuid|
    end

    test "generates correct SQL for boolean type" do
      [sql] = Postgres.generate([{:alter_column, :items, :active, [type: :boolean]}])

      assert sql =~ ~s|TYPE boolean|
    end
  end

  describe "vector type SQL generation" do
    test "generates vector column with size" do
      table = %Table{
        name: :embeddings,
        columns: [
          %Column{name: :id, type: :serial, primary_key: true},
          %Column{name: :embedding, type: :vector, size: 1536}
        ]
      }

      [sql] = Postgres.generate([{:create_table, :embeddings, table}])

      assert sql =~ ~s|"embedding" vector(1536)|
    end

    test "generates alter column for vector size" do
      [sql] =
        Postgres.generate([{:alter_column, :embeddings, :embedding, [{:size, 768, :vector}]}])

      assert sql =~ ~s|TYPE vector(768)|
    end
  end

  describe "raw SQL execution" do
    test "passes through raw SQL statements" do
      sql = "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";"

      assert Postgres.generate([{:execute_sql, sql}]) == [sql]
    end
  end
end
