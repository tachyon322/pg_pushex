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

    test "resolves drop_table when user selects 1" do
      send(self(), {:mix_shell_input, :prompt, "1\n"})

      result = Interactive.resolve_renames([{:drop_table, :legacy}])

      assert result == {:ok, [{:drop_table, :legacy}]}
      assert_received {:mix_shell, :info, [msg]}

      assert IO.ANSI.format(msg) |> IO.iodata_to_binary() =~
               "[WARNING] You are about to delete table 'legacy':"
    end

    test "aborts drop_table when user selects 2" do
      send(self(), {:mix_shell_input, :prompt, "2\n"})

      result = Interactive.resolve_renames([{:drop_table, :legacy}])

      assert result == :abort
    end

    test "resolves rename when user selects 1" do
      dropped = %Column{name: :name, type: :string}
      added = %Column{name: :first_name, type: :string}

      send(self(), {:mix_shell_input, :prompt, "1\n"})

      result =
        Interactive.resolve_renames([
          {:check_column_renames, :users, [dropped], [added]}
        ])

      assert result == {:ok, [{:rename_column, :users, :name, :first_name}]}
      assert_received {:mix_shell, :info, [msg]}

      assert IO.ANSI.format(msg) |> IO.iodata_to_binary() =~
               "[WARNING] Structural changes detected in table 'users'"
    end

    test "generates drop and add when user selects 2" do
      dropped = %Column{name: :name, type: :string}
      added = %Column{name: :first_name, type: :string}

      send(self(), {:mix_shell_input, :prompt, "2\n"})

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

    test "aborts when user selects 3" do
      dropped = %Column{name: :name, type: :string}
      added = %Column{name: :first_name, type: :string}

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

      send(self(), {:mix_shell_input, :prompt, "invalid\n"})

      result =
        Interactive.resolve_renames([
          {:check_column_renames, :users, [dropped], [added]}
        ])

      assert result == :abort
    end

    test "handles pure drop correctly (user selects 1)" do
      dropped = %Column{name: :name, type: :string}

      send(self(), {:mix_shell_input, :prompt, "1\n"})

      result =
        Interactive.resolve_renames([
          {:check_column_renames, :users, [dropped], []}
        ])

      assert result == {:ok, [{:drop_column, :users, :name}]}
      assert_received {:mix_shell, :info, [msg]}

      assert IO.ANSI.format(msg) |> IO.iodata_to_binary() =~
               "[WARNING] You are about to delete column(s) from table 'users':"
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

      # dropped_a vs added_x -> 1 (rename name->first_name)
      send(self(), {:mix_shell_input, :prompt, "1\n"})
      # dropped_b vs added_y -> 2 (different column)
      send(self(), {:mix_shell_input, :prompt, "2\n"})

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

      # dropped vs added_x -> 2
      send(self(), {:mix_shell_input, :prompt, "2\n"})
      # dropped vs added_y -> 1
      send(self(), {:mix_shell_input, :prompt, "1\n"})

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

      # User confirms drop_table with 1
      send(self(), {:mix_shell_input, :prompt, "1\n"})
      # User confirms rename with 1
      send(self(), {:mix_shell_input, :prompt, "1\n"})

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
