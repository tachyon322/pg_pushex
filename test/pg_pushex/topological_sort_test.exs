defmodule PgPushex.TopologicalSortTest do
  use ExUnit.Case, async: true

  alias PgPushex.Diff
  alias PgPushex.State.{Column, Schema, Table}

  describe "topological sort for create_table and drop_table" do
    test "sorts create_table correctly based on references" do
      users = %Table{name: :users, columns: [%Column{name: :id, type: :uuid}]}

      posts = %Table{
        name: :posts,
        columns: [%Column{name: :user_id, type: :uuid, references: :users}]
      }

      tags = %Table{name: :tags, columns: [%Column{name: :id, type: :serial}]}

      post_tags = %Table{
        name: :post_tags,
        columns: [
          %Column{name: :post_id, type: :serial, references: :posts},
          %Column{name: :tag_id, type: :serial, references: :tags}
        ]
      }

      current_schema = Schema.new()

      desired_schema =
        Schema.new()
        |> Schema.add_table(post_tags)
        |> Schema.add_table(posts)
        |> Schema.add_table(tags)
        |> Schema.add_table(users)

      ops = Diff.compare(current_schema, desired_schema)

      # Extract create_table operations in order
      created_tables =
        ops
        |> Enum.filter(fn op -> elem(op, 0) == :create_table end)
        |> Enum.map(fn {:create_table, name, _} -> name end)

      assert created_tables == [:tags, :users, :posts, :post_tags]
    end

    test "sorts drop_table correctly based on reverse references" do
      users = %Table{name: :users, columns: [%Column{name: :id, type: :uuid}]}

      posts = %Table{
        name: :posts,
        columns: [%Column{name: :user_id, type: :uuid, references: :users}]
      }

      tags = %Table{name: :tags, columns: [%Column{name: :id, type: :serial}]}

      post_tags = %Table{
        name: :post_tags,
        columns: [
          %Column{name: :post_id, type: :serial, references: :posts},
          %Column{name: :tag_id, type: :serial, references: :tags}
        ]
      }

      current_schema =
        Schema.new()
        |> Schema.add_table(post_tags)
        |> Schema.add_table(posts)
        |> Schema.add_table(tags)
        |> Schema.add_table(users)

      desired_schema = Schema.new()

      ops = Diff.compare(current_schema, desired_schema)

      # Extract drop_table operations in order
      dropped_tables =
        ops
        |> Enum.filter(fn op -> elem(op, 0) == :drop_table end)
        |> Enum.map(fn {:drop_table, name} -> name end)

      assert dropped_tables == [:post_tags, :posts, :users, :tags] or
               dropped_tables == [:post_tags, :posts, :tags, :users]
    end
  end
end
