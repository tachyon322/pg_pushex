defmodule PgPushex.CLI.InteractiveTest do
  use ExUnit.Case, async: false

  alias PgPushex.State.Column
  alias PgPushex.CLI.Interactive

  setup do
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(previous_shell) end)
    :ok
  end

  describe "resolve_renames/1" do
    test "passes through non-rename operations unchanged" do
      operations = [
        {:create_table, :posts, %PgPushex.State.Table{name: :posts, columns: []}},
        {:add_column, :users, %Column{name: :email, type: :string}},
        {:drop_column, :users, :old_field}
      ]

      assert Interactive.resolve_renames(operations) == {:ok, operations}
    end

    test "resolves drop_table when user confirms" do
      send(self(), {:mix_shell_input, :yes?, true})

      result = Interactive.resolve_renames([{:drop_table, :legacy}])

      assert result == {:ok, [{:drop_table, :legacy}]}
    end

    test "aborts drop_table when user declines" do
      send(self(), {:mix_shell_input, :yes?, false})

      result = Interactive.resolve_renames([{:drop_table, :legacy}])

      assert result == :abort
    end

    test "resolves rename when user selects rename option" do
      dropped = %Column{name: :name, type: :string}
      added = %Column{name: :first_name, type: :string}

      # Menu: 1=drop+add, 2=rename name->first_name, 3=abort
      send(self(), {:mix_shell_input, :prompt, "2\n"})

      result =
        Interactive.resolve_renames([
          {:check_column_renames, :users, [dropped], [added]}
        ])

      assert result == {:ok, [{:rename_column, :users, :name, :first_name}]}
    end

    test "generates drop and add when user selects drop_and_add option" do
      dropped = %Column{name: :name, type: :string}
      added = %Column{name: :first_name, type: :string}

      # Menu: 1=drop+add, 2=rename, 3=abort
      send(self(), {:mix_shell_input, :prompt, "1\n"})

      result =
        Interactive.resolve_renames([
          {:check_column_renames, :users, [dropped], [added]}
        ])

      assert result ==
               {:ok,
                [
                  {:drop_column, :users, :name},
                  {:add_column, :users, added}
                ]}
    end

    test "aborts when user selects abort option" do
      dropped = %Column{name: :name, type: :string}
      added = %Column{name: :first_name, type: :string}

      # Menu: 1=drop+add, 2=rename, 3=abort
      send(self(), {:mix_shell_input, :prompt, "3\n"})

      result =
        Interactive.resolve_renames([
          {:check_column_renames, :users, [dropped], [added]}
        ])

      assert result == :abort
    end

    test "aborts when user provides invalid input" do
      dropped = %Column{name: :name, type: :string}
      added = %Column{name: :first_name, type: :string}

      # First invalid input triggers re-prompt, then abort (option 3)
      send(self(), {:mix_shell_input, :prompt, "invalid\n"})
      send(self(), {:mix_shell_input, :prompt, "3\n"})

      result =
        Interactive.resolve_renames([
          {:check_column_renames, :users, [dropped], [added]}
        ])

      assert result == :abort
    end

    test "handles pure drop correctly (user confirms)" do
      dropped = %Column{name: :name, type: :string}

      # Menu: 1=proceed with deletion, 2=abort
      send(self(), {:mix_shell_input, :prompt, "1\n"})

      result =
        Interactive.resolve_renames([
          {:check_column_renames, :users, [dropped], []}
        ])

      assert result == {:ok, [{:drop_column, :users, :name}]}
    end

    test "handles pure drop correctly (user selects 2 - aborts)" do
      dropped = %Column{name: :name, type: :string}

      send(self(), {:mix_shell_input, :prompt, "2\n"})

      result =
        Interactive.resolve_renames([
          {:check_column_renames, :users, [dropped], []}
        ])

      assert result == :abort
    end

    test "handles mixed scenario: one rename, one drop confirmed" do
      dropped_a = %Column{name: :name, type: :string}
      dropped_b = %Column{name: :age, type: :integer}
      added_x = %Column{name: :first_name, type: :string}
      added_y = %Column{name: :bio, type: :string}

      # First menu: 1=drop+add, 2=rename name->first_name, 3=rename name->bio,
      #            4=rename age->first_name, 5=rename age->bio, 6=abort
      # Select 2 = rename name->first_name
      send(self(), {:mix_shell_input, :prompt, "2\n"})
      # After rename, remaining: dropped_b (age) vs added_y (bio)
      # Second menu: 1=drop+add, 2=rename age->bio, 3=abort
      # Select 1 = drop+add (since age and bio are different)
      send(self(), {:mix_shell_input, :prompt, "1\n"})

      result =
        Interactive.resolve_renames([
          {:check_column_renames, :users, [dropped_a, dropped_b], [added_x, added_y]}
        ])

      assert result ==
               {:ok,
                [
                  {:rename_column, :users, :name, :first_name},
                  {:drop_column, :users, :age},
                  {:add_column, :users, added_y}
                ]}
    end

    test "skips first added and matches second" do
      dropped = %Column{name: :name, type: :string}
      added_x = %Column{name: :first_name, type: :string}
      added_y = %Column{name: :full_name, type: :string}

      # Menu: 1=drop+add, 2=rename name->first_name, 3=rename name->full_name, 4=abort
      # Select 3 = rename name->full_name (skip first_name, match with full_name)
      send(self(), {:mix_shell_input, :prompt, "3\n"})

      result =
        Interactive.resolve_renames([
          {:check_column_renames, :users, [dropped], [added_x, added_y]}
        ])

      assert result ==
               {:ok,
                [
                  {:rename_column, :users, :name, :full_name},
                  {:add_column, :users, added_x}
                ]}
    end

    test "preserves other operations alongside rename resolution" do
      dropped = %Column{name: :name, type: :string}
      added = %Column{name: :first_name, type: :string}

      # User confirms drop_table with yes
      send(self(), {:mix_shell_input, :yes?, true})
      # Menu: 1=drop+add, 2=rename name->first_name, 3=abort
      # User selects rename (2)
      send(self(), {:mix_shell_input, :prompt, "2\n"})

      result =
        Interactive.resolve_renames([
          {:drop_table, :legacy},
          {:check_column_renames, :users, [dropped], [added]},
          {:alter_column, :users, :email, [null: false]}
        ])

      assert result ==
               {:ok,
                [
                  {:drop_table, :legacy},
                  {:rename_column, :users, :name, :first_name},
                  {:alter_column, :users, :email, [null: false]}
                ]}
    end
  end
end
