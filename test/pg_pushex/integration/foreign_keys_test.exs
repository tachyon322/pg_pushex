defmodule PgPushex.Integration.ForeignKeysTest do
  use PgPushex.Integration.TestCase, async: false

  @moduletag :integration

  describe "creating tables with foreign keys" do
    test "creates tables in correct order based on FK dependencies" do
      desired =
        build_schema([
          build_table(:posts, [
            build_column(:id, :serial, primary_key: true),
            build_column(:title, :string)
          ]),
          build_table(
            :comments,
            [
              build_column(:id, :serial, primary_key: true),
              build_column(:post_id, :integer, references: :posts)
            ],
            foreign_keys: [
              %ForeignKey{
                column_name: :post_id,
                referenced_table: :posts,
                referenced_column: :id,
                on_delete: :nothing,
                on_update: :nothing
              }
            ]
          )
        ])

      push_schema!(desired)

      result =
        execute_sql(
          "SELECT COUNT(*) FROM information_schema.table_constraints WHERE table_name = 'comments' AND constraint_type = 'FOREIGN KEY';"
        )

      assert result.rows == [[1]]
    end

    test "creates multiple tables with chain of FK dependencies" do
      desired =
        build_schema([
          build_table(:authors, [
            build_column(:id, :serial, primary_key: true),
            build_column(:name, :string)
          ]),
          build_table(
            :posts,
            [
              build_column(:id, :serial, primary_key: true),
              build_column(:author_id, :integer, references: :authors)
            ],
            foreign_keys: [
              %ForeignKey{
                column_name: :author_id,
                referenced_table: :authors,
                referenced_column: :id,
                on_delete: :nothing,
                on_update: :nothing
              }
            ]
          ),
          build_table(
            :comments,
            [
              build_column(:id, :serial, primary_key: true),
              build_column(:post_id, :integer, references: :posts)
            ],
            foreign_keys: [
              %ForeignKey{
                column_name: :post_id,
                referenced_table: :posts,
                referenced_column: :id,
                on_delete: :nothing,
                on_update: :nothing
              }
            ]
          )
        ])

      push_schema!(desired)

      result =
        execute_sql(
          "SELECT COUNT(*) FROM information_schema.table_constraints WHERE constraint_type = 'FOREIGN KEY';"
        )

      assert result.rows == [[2]]
    end
  end

  describe "dropping tables with foreign keys" do
    test "drops tables in correct reverse order" do
      execute_sql("CREATE TABLE authors (id serial PRIMARY KEY);")

      execute_sql(
        "CREATE TABLE posts (id serial PRIMARY KEY, author_id integer REFERENCES authors(id));"
      )

      desired =
        build_schema([
          build_table(:authors, [
            build_column(:id, :serial, primary_key: true)
          ])
        ])

      push_schema!(desired)

      assert_raise Postgrex.Error, ~r/relation "posts" does not exist/, fn ->
        execute_sql("SELECT * FROM posts;")
      end
    end

    test "fails when trying to drop table referenced by another table without dropping the dependent" do
      execute_sql("CREATE TABLE authors (id serial PRIMARY KEY);")

      execute_sql(
        "CREATE TABLE posts (id serial PRIMARY KEY, author_id integer REFERENCES authors(id));"
      )

      desired =
        build_schema([
          build_table(:posts, [
            build_column(:id, :serial, primary_key: true),
            build_column(:author_id, :integer)
          ])
        ])

      assert_raise Postgrex.Error,
                   ~r/cannot drop table .* because other objects depend on it/,
                   fn ->
                     push_schema!(desired)
                   end
    end
  end

  describe "foreign key actions" do
    test "creates FK with ON DELETE CASCADE" do
      execute_sql("CREATE TABLE posts (id serial PRIMARY KEY);")

      desired =
        build_schema([
          build_table(:posts, [
            build_column(:id, :serial, primary_key: true)
          ]),
          build_table(
            :comments,
            [
              build_column(:id, :serial, primary_key: true),
              build_column(:post_id, :integer, references: :posts, on_delete: :cascade)
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
          )
        ])

      push_schema!(desired)

      execute_sql("INSERT INTO posts DEFAULT VALUES;")
      execute_sql("INSERT INTO comments (post_id) VALUES (1);")
      execute_sql("DELETE FROM posts WHERE id = 1;")

      result = execute_sql("SELECT COUNT(*) FROM comments;")
      assert result.rows == [[0]]
    end

    test "creates FK with ON DELETE SET NULL" do
      execute_sql("CREATE TABLE posts (id serial PRIMARY KEY);")

      desired =
        build_schema([
          build_table(:posts, [
            build_column(:id, :serial, primary_key: true)
          ]),
          build_table(
            :comments,
            [
              build_column(:id, :serial, primary_key: true),
              build_column(:post_id, :integer, references: :posts, on_delete: :set_null)
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
          )
        ])

      push_schema!(desired)

      execute_sql("INSERT INTO posts DEFAULT VALUES;")
      execute_sql("INSERT INTO comments (post_id) VALUES (1);")
      execute_sql("DELETE FROM posts WHERE id = 1;")

      result = execute_sql("SELECT post_id FROM comments;")
      assert result.rows == [[nil]]
    end

    test "creates FK with ON DELETE RESTRICT" do
      execute_sql("CREATE TABLE posts (id serial PRIMARY KEY);")

      desired =
        build_schema([
          build_table(:posts, [
            build_column(:id, :serial, primary_key: true)
          ]),
          build_table(
            :comments,
            [
              build_column(:id, :serial, primary_key: true),
              build_column(:post_id, :integer, references: :posts, on_delete: :restrict)
            ],
            foreign_keys: [
              %ForeignKey{
                column_name: :post_id,
                referenced_table: :posts,
                referenced_column: :id,
                on_delete: :restrict,
                on_update: :nothing
              }
            ]
          )
        ])

      push_schema!(desired)

      execute_sql("INSERT INTO posts DEFAULT VALUES;")
      execute_sql("INSERT INTO comments (post_id) VALUES (1);")

      assert_raise Postgrex.Error, ~r/violates foreign key constraint/, fn ->
        execute_sql("DELETE FROM posts WHERE id = 1;")
      end
    end
  end

  describe "adding foreign key to existing table" do
    test "adds FK to existing column" do
      execute_sql("CREATE TABLE posts (id serial PRIMARY KEY);")
      execute_sql("CREATE TABLE comments (id serial PRIMARY KEY, post_id integer);")

      desired =
        build_schema([
          build_table(:posts, [
            build_column(:id, :serial, primary_key: true)
          ]),
          build_table(
            :comments,
            [
              build_column(:id, :serial, primary_key: true),
              build_column(:post_id, :integer, references: :posts)
            ],
            foreign_keys: [
              %ForeignKey{
                column_name: :post_id,
                referenced_table: :posts,
                referenced_column: :id,
                on_delete: :nothing,
                on_update: :nothing
              }
            ]
          )
        ])

      push_schema!(desired)

      result =
        execute_sql(
          "SELECT COUNT(*) FROM information_schema.table_constraints WHERE table_name = 'comments' AND constraint_type = 'FOREIGN KEY';"
        )

      assert result.rows == [[1]]
    end

    test "fails when adding FK with invalid data" do
      execute_sql("CREATE TABLE posts (id serial PRIMARY KEY);")
      execute_sql("CREATE TABLE comments (id serial PRIMARY KEY, post_id integer);")
      execute_sql("INSERT INTO comments (post_id) VALUES (999);")

      desired =
        build_schema([
          build_table(:posts, [
            build_column(:id, :serial, primary_key: true)
          ]),
          build_table(
            :comments,
            [
              build_column(:id, :serial, primary_key: true),
              build_column(:post_id, :integer, references: :posts)
            ],
            foreign_keys: [
              %ForeignKey{
                column_name: :post_id,
                referenced_table: :posts,
                referenced_column: :id,
                on_delete: :nothing,
                on_update: :nothing
              }
            ]
          )
        ])

      assert_raise Postgrex.Error, ~r/violates foreign key constraint/, fn ->
        push_schema!(desired)
      end
    end
  end

  describe "removing foreign key" do
    test "removes FK but keeps column" do
      execute_sql("CREATE TABLE posts (id serial PRIMARY KEY);")

      execute_sql(
        "CREATE TABLE comments (id serial PRIMARY KEY, post_id integer REFERENCES posts(id));"
      )

      desired =
        build_schema([
          build_table(:posts, [
            build_column(:id, :serial, primary_key: true)
          ]),
          build_table(:comments, [
            build_column(:id, :serial, primary_key: true),
            build_column(:post_id, :integer)
          ])
        ])

      push_schema!(desired)

      result =
        execute_sql(
          "SELECT COUNT(*) FROM information_schema.table_constraints WHERE table_name = 'comments' AND constraint_type = 'FOREIGN KEY';"
        )

      assert result.rows == [[0]]
    end
  end

  describe "introspecting foreign keys" do
    test "correctly reads FK with CASCADE action" do
      execute_sql("CREATE TABLE posts (id serial PRIMARY KEY);")

      execute_sql(
        "CREATE TABLE comments (id serial PRIMARY KEY, post_id integer REFERENCES posts(id) ON DELETE CASCADE);"
      )

      schema = introspect_schema()

      comments_table = schema.tables[:comments]
      assert comments_table != nil

      fk = Enum.find(comments_table.foreign_keys, &(&1.column_name == :post_id))
      assert fk != nil
      assert fk.referenced_table == :posts
      assert fk.on_delete == :cascade
    end

    test "correctly reads FK with SET NULL action" do
      execute_sql("CREATE TABLE posts (id serial PRIMARY KEY);")

      execute_sql(
        "CREATE TABLE comments (id serial PRIMARY KEY, post_id integer REFERENCES posts(id) ON DELETE SET NULL);"
      )

      schema = introspect_schema()

      comments_table = schema.tables[:comments]
      fk = Enum.find(comments_table.foreign_keys, &(&1.column_name == :post_id))
      assert fk.on_delete == :set_null
    end

    test "correctly reads FK with RESTRICT action" do
      execute_sql("CREATE TABLE posts (id serial PRIMARY KEY);")

      execute_sql(
        "CREATE TABLE comments (id serial PRIMARY KEY, post_id integer REFERENCES posts(id) ON DELETE RESTRICT);"
      )

      schema = introspect_schema()

      comments_table = schema.tables[:comments]
      fk = Enum.find(comments_table.foreign_keys, &(&1.column_name == :post_id))
      assert fk.on_delete == :restrict
    end

    test "correctly reads FK with ON UPDATE action" do
      execute_sql("CREATE TABLE posts (id serial PRIMARY KEY);")

      execute_sql(
        "CREATE TABLE comments (id serial PRIMARY KEY, post_id integer REFERENCES posts(id) ON UPDATE CASCADE);"
      )

      schema = introspect_schema()

      comments_table = schema.tables[:comments]
      fk = Enum.find(comments_table.foreign_keys, &(&1.column_name == :post_id))
      assert fk.on_update == :cascade
    end
  end

  describe "changing FK action" do
    test "detects on_delete change from cascade to restrict" do
      execute_sql("CREATE TABLE posts (id serial PRIMARY KEY);")

      execute_sql(
        "CREATE TABLE comments (id serial PRIMARY KEY, post_id integer REFERENCES posts(id) ON DELETE CASCADE);"
      )

      desired =
        build_schema([
          build_table(:posts, [
            build_column(:id, :serial, primary_key: true)
          ]),
          build_table(
            :comments,
            [
              build_column(:id, :serial, primary_key: true),
              build_column(:post_id, :integer, references: :posts, on_delete: :restrict)
            ],
            foreign_keys: [
              %ForeignKey{
                column_name: :post_id,
                referenced_table: :posts,
                referenced_column: :id,
                on_delete: :restrict,
                on_update: :nothing
              }
            ]
          )
        ])

      current = introspect_schema()
      operations = Diff.compare(current, desired)

      assert Enum.any?(operations, fn
               {:alter_column, :comments, :post_id, [{:on_delete, :restrict, :posts}]} -> true
               _ -> false
             end)
    end
  end

  describe "self-referencing foreign key" do
    test "creates table with self-referencing FK" do
      desired =
        build_schema([
          build_table(
            :categories,
            [
              build_column(:id, :serial, primary_key: true),
              build_column(:parent_id, :integer, references: :categories)
            ],
            foreign_keys: [
              %ForeignKey{
                column_name: :parent_id,
                referenced_table: :categories,
                referenced_column: :id,
                on_delete: :nothing,
                on_update: :nothing
              }
            ]
          )
        ])

      push_schema!(desired)

      execute_sql("INSERT INTO categories DEFAULT VALUES;")
      execute_sql("INSERT INTO categories (parent_id) VALUES (1);")

      result = execute_sql("SELECT parent_id FROM categories WHERE id = 2;")
      assert result.rows == [[1]]
    end
  end

  describe "multiple foreign keys from one table" do
    test "creates table with multiple FKs" do
      desired =
        build_schema([
          build_table(:users, [
            build_column(:id, :serial, primary_key: true)
          ]),
          build_table(:posts, [
            build_column(:id, :serial, primary_key: true)
          ]),
          build_table(
            :comments,
            [
              build_column(:id, :serial, primary_key: true),
              build_column(:user_id, :integer, references: :users),
              build_column(:post_id, :integer, references: :posts)
            ],
            foreign_keys: [
              %ForeignKey{
                column_name: :user_id,
                referenced_table: :users,
                referenced_column: :id,
                on_delete: :nothing,
                on_update: :nothing
              },
              %ForeignKey{
                column_name: :post_id,
                referenced_table: :posts,
                referenced_column: :id,
                on_delete: :nothing,
                on_update: :nothing
              }
            ]
          )
        ])

      push_schema!(desired)

      result =
        execute_sql(
          "SELECT COUNT(*) FROM information_schema.table_constraints WHERE table_name = 'comments' AND constraint_type = 'FOREIGN KEY';"
        )

      assert result.rows == [[2]]
    end
  end
end
