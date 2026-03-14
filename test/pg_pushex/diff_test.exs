defmodule PgPushex.DiffTest do
  use ExUnit.Case, async: true

  alias PgPushex.Diff
  alias PgPushex.State.{Column, ForeignKey, Index, Schema, Table}

  describe "compare/2" do
    test "returns create_table for a new table" do
      users_table =
        %Table{
          name: :users,
          columns: [
            %Column{name: :id, type: :uuid, null: false, primary_key: true}
          ]
        }

      current_schema = Schema.new()
      desired_schema = Schema.add_table(Schema.new(), users_table)

      assert Diff.compare(current_schema, desired_schema) ==
               [{:create_table, :users, users_table}]
    end

    test "returns drop_table for a table missing from desired schema" do
      users_table =
        %Table{
          name: :users,
          columns: [
            %Column{name: :id, type: :uuid, null: false, primary_key: true}
          ]
        }

      current_schema = Schema.add_table(Schema.new(), users_table)
      desired_schema = Schema.new()

      assert Diff.compare(current_schema, desired_schema) == [{:drop_table, :users}]
    end

    test "returns add_column for a new column in existing table" do
      id_column = %Column{name: :id, type: :uuid, null: false, primary_key: true}
      email_column = %Column{name: :email, type: :string}

      current_users = %Table{name: :users, columns: [id_column]}
      desired_users = %Table{name: :users, columns: [id_column, email_column]}

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      assert Diff.compare(current_schema, desired_schema) ==
               [{:add_column, :users, email_column}]
    end

    test "returns alter_column when null property changes" do
      current_users =
        %Table{
          name: :users,
          columns: [
            %Column{name: :email, type: :string, null: true}
          ]
        }

      desired_users =
        %Table{
          name: :users,
          columns: [
            %Column{name: :email, type: :string, null: false}
          ]
        }

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      assert Diff.compare(current_schema, desired_schema) ==
               [{:alter_column, :users, :email, [null: false]}]
    end

    test "returns no change when schema uses :bool alias and DB has :boolean" do
      current_users = %Table{name: :users, columns: [%Column{name: :flag, type: :boolean}]}
      desired_users = %Table{name: :users, columns: [%Column{name: :flag, type: :bool}]}

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      assert Diff.compare(current_schema, desired_schema) == []
    end

    test "returns no change when schema uses :int alias and DB has :integer" do
      current_users = %Table{name: :users, columns: [%Column{name: :count, type: :integer}]}
      desired_users = %Table{name: :users, columns: [%Column{name: :count, type: :int}]}

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      assert Diff.compare(current_schema, desired_schema) == []
    end

    test "returns no change when schema uses :binary_id alias and DB has :binary" do
      current_users = %Table{name: :users, columns: [%Column{name: :data, type: :binary}]}
      desired_users = %Table{name: :users, columns: [%Column{name: :data, type: :binary_id}]}

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      assert Diff.compare(current_schema, desired_schema) == []
    end

    test "returns check_column_renames when dropped and added columns coexist" do
      dropped_name_column = %Column{name: :name, type: :string}
      added_first_name_column = %Column{name: :first_name, type: :string}

      current_users = %Table{name: :users, columns: [dropped_name_column]}
      desired_users = %Table{name: :users, columns: [added_first_name_column]}

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      assert Diff.compare(current_schema, desired_schema) ==
               [
                 {:check_column_renames, :users, [dropped_name_column], [added_first_name_column]}
               ]
    end

    test "returns no change when on_delete uses delete_all alias and DB has cascade" do
      current_users = %Table{
        name: :users,
        columns: [%Column{name: :post_id, type: :integer}],
        foreign_keys: [
          %PgPushex.State.ForeignKey{
            column_name: :post_id,
            referenced_table: :posts,
            referenced_column: :id,
            on_delete: :cascade,
            on_update: :nothing
          }
        ]
      }

      desired_users = %Table{
        name: :users,
        columns: [%Column{name: :post_id, type: :integer}],
        foreign_keys: [
          %PgPushex.State.ForeignKey{
            column_name: :post_id,
            referenced_table: :posts,
            referenced_column: :id,
            on_delete: :delete_all,
            on_update: :nothing
          }
        ]
      }

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      assert Diff.compare(current_schema, desired_schema) == []
    end

    test "returns no change when on_delete uses nilify_all alias and DB has set_null" do
      current_users = %Table{
        name: :users,
        columns: [%Column{name: :post_id, type: :integer}],
        foreign_keys: [
          %PgPushex.State.ForeignKey{
            column_name: :post_id,
            referenced_table: :posts,
            referenced_column: :id,
            on_delete: :set_null,
            on_update: :nothing
          }
        ]
      }

      desired_users = %Table{
        name: :users,
        columns: [%Column{name: :post_id, type: :integer}],
        foreign_keys: [
          %PgPushex.State.ForeignKey{
            column_name: :post_id,
            referenced_table: :posts,
            referenced_column: :id,
            on_delete: :nilify_all,
            on_update: :nothing
          }
        ]
      }

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      assert Diff.compare(current_schema, desired_schema) == []
    end
  end

  describe "topological sorting for table operations" do
    test "creates tables in correct order based on FK dependencies" do
      posts_table = %Table{
        name: :posts,
        columns: [%Column{name: :id, type: :serial, primary_key: true}]
      }

      comments_table = %Table{
        name: :comments,
        columns: [
          %Column{name: :id, type: :serial, primary_key: true},
          %Column{name: :post_id, type: :integer, references: :posts}
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
      }

      current_schema = Schema.new()
      desired_schema = %Schema{tables: %{posts: posts_table, comments: comments_table}}

      operations = Diff.compare(current_schema, desired_schema)

      create_posts_idx =
        Enum.find_index(operations, fn
          {:create_table, :posts, _} -> true
          _ -> false
        end)

      create_comments_idx =
        Enum.find_index(operations, fn
          {:create_table, :comments, _} -> true
          _ -> false
        end)

      assert create_posts_idx < create_comments_idx
    end

    test "drops tables in reverse order of FK dependencies" do
      posts_table = %Table{
        name: :posts,
        columns: [%Column{name: :id, type: :serial, primary_key: true}]
      }

      comments_table = %Table{
        name: :comments,
        columns: [
          %Column{name: :id, type: :serial, primary_key: true},
          %Column{name: :post_id, type: :integer, references: :posts}
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
      }

      current_schema = %Schema{tables: %{posts: posts_table, comments: comments_table}}
      desired_schema = Schema.new()

      operations = Diff.compare(current_schema, desired_schema)

      drop_posts_idx =
        Enum.find_index(operations, fn
          {:drop_table, :posts} -> true
          _ -> false
        end)

      drop_comments_idx =
        Enum.find_index(operations, fn
          {:drop_table, :comments} -> true
          _ -> false
        end)

      assert drop_comments_idx < drop_posts_idx
    end

    test "handles chain of FK dependencies" do
      authors = %Table{
        name: :authors,
        columns: [%Column{name: :id, type: :serial, primary_key: true}]
      }

      posts = %Table{
        name: :posts,
        columns: [
          %Column{name: :id, type: :serial, primary_key: true},
          %Column{name: :author_id, type: :integer, references: :authors}
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
      }

      comments = %Table{
        name: :comments,
        columns: [
          %Column{name: :id, type: :serial, primary_key: true},
          %Column{name: :post_id, type: :integer, references: :posts}
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
      }

      current_schema = Schema.new()
      desired_schema = %Schema{tables: %{authors: authors, posts: posts, comments: comments}}

      operations = Diff.compare(current_schema, desired_schema)

      [authors_idx, posts_idx, comments_idx] =
        [:authors, :posts, :comments]
        |> Enum.map(fn table ->
          Enum.find_index(operations, fn
            {:create_table, ^table, _} -> true
            _ -> false
          end)
        end)

      assert authors_idx < posts_idx
      assert posts_idx < comments_idx
    end
  end

  describe "string column size changes" do
    test "detects size change for string column" do
      current_users = %Table{
        name: :users,
        columns: [%Column{name: :name, type: :string, size: 100}]
      }

      desired_users = %Table{
        name: :users,
        columns: [%Column{name: :name, type: :string, size: 50}]
      }

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      assert Diff.compare(current_schema, desired_schema) ==
               [{:alter_column, :users, :name, [{:size, 50, :string}]}]
    end

    test "detects adding size constraint to string column" do
      current_users = %Table{
        name: :users,
        columns: [%Column{name: :name, type: :string}]
      }

      desired_users = %Table{
        name: :users,
        columns: [%Column{name: :name, type: :string, size: 100}]
      }

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      assert Diff.compare(current_schema, desired_schema) ==
               [{:alter_column, :users, :name, [{:size, 100, :string}]}]
    end

    test "detects removing size constraint from string column" do
      current_users = %Table{
        name: :users,
        columns: [%Column{name: :name, type: :string, size: 100}]
      }

      desired_users = %Table{
        name: :users,
        columns: [%Column{name: :name, type: :string}]
      }

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      assert Diff.compare(current_schema, desired_schema) ==
               [{:alter_column, :users, :name, [{:size, nil, :string}]}]
    end

    test "no change when size stays the same" do
      current_users = %Table{
        name: :users,
        columns: [%Column{name: :name, type: :string, size: 100}]
      }

      desired_users = %Table{
        name: :users,
        columns: [%Column{name: :name, type: :string, size: 100}]
      }

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      assert Diff.compare(current_schema, desired_schema) == []
    end
  end

  describe "generated column changes" do
    test "returns recreate_generated_column when expression changes" do
      current_users = %Table{
        name: :users,
        columns: [
          %Column{name: :id, type: :serial, primary_key: true},
          %Column{name: :name, type: :string},
          %Column{name: :upper_name, type: :string, generated_as: {:fragment, "upper(name)"}}
        ]
      }

      desired_users = %Table{
        name: :users,
        columns: [
          %Column{name: :id, type: :serial, primary_key: true},
          %Column{name: :name, type: :string},
          %Column{name: :upper_name, type: :string, generated_as: {:fragment, "lower(name)"}}
        ]
      }

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      operations = Diff.compare(current_schema, desired_schema)

      assert Enum.any?(operations, fn
               {:recreate_generated_column, :users, :upper_name, _} -> true
               _ -> false
             end)
    end

    test "detects removal of generated expression" do
      current_users = %Table{
        name: :users,
        columns: [
          %Column{name: :id, type: :serial, primary_key: true},
          %Column{name: :name, type: :string},
          %Column{name: :upper_name, type: :string, generated_as: {:fragment, "upper(name)"}}
        ]
      }

      desired_users = %Table{
        name: :users,
        columns: [
          %Column{name: :id, type: :serial, primary_key: true},
          %Column{name: :name, type: :string},
          %Column{name: :upper_name, type: :string}
        ]
      }

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      operations = Diff.compare(current_schema, desired_schema)

      assert Enum.any?(operations, fn
               {:alter_column, :users, :upper_name, [{:generated_as, nil}]} -> true
               _ -> false
             end)
    end
  end

  describe "enum operations" do
    test "detects new enum type for new table" do
      desired_users = %Table{
        name: :users,
        columns: [
          %Column{name: :id, type: :serial, primary_key: true},
          %Column{name: :status, type: :string, enum: ["active", "inactive"]}
        ]
      }

      current_schema = Schema.new()
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      operations = Diff.compare(current_schema, desired_schema)

      assert Enum.any?(operations, fn
               {:create_type_enum, "users_status_enum", ["active", "inactive"]} -> true
               _ -> false
             end)
    end

    test "detects new enum values added" do
      current_users = %Table{
        name: :users,
        columns: [
          %Column{name: :id, type: :serial, primary_key: true},
          %Column{name: :status, type: :string, enum: ["active", "inactive"]}
        ]
      }

      desired_users = %Table{
        name: :users,
        columns: [
          %Column{name: :id, type: :serial, primary_key: true},
          %Column{name: :status, type: :string, enum: ["active", "inactive", "pending"]}
        ]
      }

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      operations = Diff.compare(current_schema, desired_schema)

      assert Enum.any?(operations, fn
               {:alter_enum, "users_status_enum", ["pending"]} -> true
               _ -> false
             end)
    end

    test "no change when enum values are the same" do
      users_table = %Table{
        name: :users,
        columns: [
          %Column{name: :id, type: :serial, primary_key: true},
          %Column{name: :status, type: :string, enum: ["active", "inactive"]}
        ]
      }

      current_schema = Schema.add_table(Schema.new(), users_table)
      desired_schema = Schema.add_table(Schema.new(), users_table)

      assert Diff.compare(current_schema, desired_schema) == []
    end
  end

  describe "index operations" do
    test "detects new index" do
      current_users = %Table{
        name: :users,
        columns: [%Column{name: :email, type: :string}]
      }

      desired_users = %Table{
        name: :users,
        columns: [%Column{name: :email, type: :string}],
        indexes: [%Index{name: :users_email_index, columns: [:email], unique: false}]
      }

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      assert Diff.compare(current_schema, desired_schema) ==
               [
                 {:create_index, :users,
                  %Index{name: :users_email_index, columns: [:email], unique: false}}
               ]
    end

    test "detects dropped index" do
      current_users = %Table{
        name: :users,
        columns: [%Column{name: :email, type: :string}],
        indexes: [%Index{name: :users_email_index, columns: [:email], unique: false}]
      }

      desired_users = %Table{
        name: :users,
        columns: [%Column{name: :email, type: :string}]
      }

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      assert Diff.compare(current_schema, desired_schema) ==
               [{:drop_index, :users, :users_email_index}]
    end

    test "detects index columns change (drop and recreate)" do
      current_users = %Table{
        name: :users,
        columns: [%Column{name: :email, type: :string}, %Column{name: :name, type: :string}],
        indexes: [%Index{name: :users_email_index, columns: [:email], unique: false}]
      }

      desired_users = %Table{
        name: :users,
        columns: [%Column{name: :email, type: :string}, %Column{name: :name, type: :string}],
        indexes: [%Index{name: :users_email_index, columns: [:email, :name], unique: false}]
      }

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      operations = Diff.compare(current_schema, desired_schema)

      assert {:drop_index, :users, :users_email_index} in operations

      assert Enum.any?(operations, fn
               {:create_index, :users, %Index{name: :users_email_index, columns: [:email, :name]}} ->
                 true

               _ ->
                 false
             end)
    end

    test "detects uniqueness change (drop and recreate)" do
      current_users = %Table{
        name: :users,
        columns: [%Column{name: :email, type: :string}],
        indexes: [%Index{name: :users_email_index, columns: [:email], unique: false}]
      }

      desired_users = %Table{
        name: :users,
        columns: [%Column{name: :email, type: :string}],
        indexes: [%Index{name: :users_email_index, columns: [:email], unique: true}]
      }

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      operations = Diff.compare(current_schema, desired_schema)

      assert {:drop_index, :users, :users_email_index} in operations

      assert Enum.any?(operations, fn
               {:create_index, :users, %Index{name: :users_email_index, unique: true}} -> true
               _ -> false
             end)
    end
  end

  describe "foreign key action changes" do
    test "detects on_delete change from cascade to restrict" do
      current_users = %Table{
        name: :users,
        columns: [%Column{name: :post_id, type: :integer}],
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

      desired_users = %Table{
        name: :users,
        columns: [%Column{name: :post_id, type: :integer}],
        foreign_keys: [
          %ForeignKey{
            column_name: :post_id,
            referenced_table: :posts,
            referenced_column: :id,
            on_delete: :restrict,
            on_update: :nothing
          }
        ]
      }

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      operations = Diff.compare(current_schema, desired_schema)

      assert Enum.any?(operations, fn
               {:alter_column, :users, :post_id, [{:on_delete, :restrict, :posts, :id, nil}]} ->
                 true

               _ ->
                 false
             end)
    end

    test "detects on_update change" do
      current_users = %Table{
        name: :users,
        columns: [%Column{name: :post_id, type: :integer}],
        foreign_keys: [
          %ForeignKey{
            column_name: :post_id,
            referenced_table: :posts,
            referenced_column: :id,
            on_delete: :nothing,
            on_update: :nothing
          }
        ]
      }

      desired_users = %Table{
        name: :users,
        columns: [%Column{name: :post_id, type: :integer}],
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

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      operations = Diff.compare(current_schema, desired_schema)

      assert Enum.any?(operations, fn
               {:alter_column, :users, :post_id, [{:on_update, :cascade, :posts, :id, nil}]} ->
                 true

               _ ->
                 false
             end)
    end
  end

  describe "multiple changes in single alter_column" do
    test "detects multiple changes for same column" do
      current_users = %Table{
        name: :users,
        columns: [%Column{name: :email, type: :string, null: true, default: nil}]
      }

      desired_users = %Table{
        name: :users,
        columns: [%Column{name: :email, type: :string, null: false, default: "test@example.com"}]
      }

      current_schema = Schema.add_table(Schema.new(), current_users)
      desired_schema = Schema.add_table(Schema.new(), desired_users)

      operations = Diff.compare(current_schema, desired_schema)

      assert [{:alter_column, :users, :email, changes}] = operations
      assert {:null, false} in changes
      assert {:default, "test@example.com"} in changes
    end
  end
end
