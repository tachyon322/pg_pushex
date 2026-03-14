defmodule PgPushex.MigratorTest do
  use ExUnit.Case, async: true

  alias PgPushex.State.{Column, Schema}
  alias PgPushex.Migrator

  defmodule SchemaStub do
    def __schema__, do: PgPushex.State.Schema.new()
  end

  defmodule IntrospectorStub do
    def introspect(repo) do
      send(self(), {:introspect_called, repo})
      PgPushex.State.Schema.new()
    end
  end

  defmodule DiffNoChangesStub do
    def compare(current_state, desired_state) do
      send(self(), {:diff_called, current_state, desired_state})
      []
    end
  end

  defmodule DiffAmbiguousRenameStub do
    def compare(_current_state, _desired_state) do
      [
        {:check_column_renames, :users, [%Column{name: :name, type: :string}],
         [%Column{name: :first_name, type: :string}]}
      ]
    end
  end

  defmodule RenameResolverStub do
    def resolve_renames(_operations) do
      {:ok, [{:rename_column, :users, :name, :first_name}]}
    end
  end

  defmodule RenameResolverPassthroughStub do
    def resolve_renames(operations), do: {:ok, operations}
  end

  defmodule RenameResolverAbortStub do
    def resolve_renames(_operations), do: :abort
  end

  defmodule DiffWithChangesStub do
    def compare(_current_state, _desired_state) do
      operations = [{:drop_table, :legacy_users}]
      send(self(), {:diff_called, operations})
      operations
    end
  end

  defmodule SQLGeneratorStub do
    def generate(operations) do
      send(self(), {:sql_generate_called, operations})

      [
        "ALTER TABLE \"users\" ADD COLUMN \"email\" text;",
        "DROP TABLE \"legacy_users\" CASCADE;"
      ]
    end
  end

  defmodule RepoSuccess do
    def transaction(fun) do
      send(self(), :transaction_called)
      {:ok, fun.()}
    end
  end

  defmodule RepoError do
    def transaction(_fun) do
      send(self(), :transaction_called)
      {:error, :tx_failed}
    end
  end

  describe "run/3" do
    test "returns {:ok, :no_changes} and does not start transaction when no changes exist" do
      log =
        ExUnit.CaptureIO.capture_io(fn ->
          assert {:ok, :no_changes} =
                   Migrator.run(RepoSuccess, SchemaStub,
                     introspector: IntrospectorStub,
                     diff: DiffNoChangesStub,
                     sql_generator: SQLGeneratorStub,
                     sql_query_fun: fn _repo, _sql ->
                       send(self(), :sql_query_called)
                       :ok
                     end
                   )
        end)

      assert_received {:introspect_called, RepoSuccess}
      assert_received {:diff_called, %Schema{}, %Schema{}}
      refute_received :transaction_called
      refute_received :sql_generate_called
      refute_received :sql_query_called
      assert log =~ "Calculating diff..."
      assert log =~ "No changes detected"
    end

    test "resolves ambiguous renames via rename_resolver before generating SQL" do
      assert {:ok, :pushed} =
               Migrator.run(RepoSuccess, SchemaStub,
                 introspector: IntrospectorStub,
                 diff: DiffAmbiguousRenameStub,
                 sql_generator: SQLGeneratorStub,
                 rename_resolver: RenameResolverStub,
                 sql_query_fun: fn _repo, _sql -> :ok end
               )

      assert_received {:sql_generate_called, [{:rename_column, :users, :name, :first_name}]}
      assert_received :transaction_called
    end

    test "executes generated SQL in a single transaction and returns {:ok, :pushed}" do
      log =
        ExUnit.CaptureIO.capture_io(fn ->
          assert {:ok, :pushed} =
                   Migrator.run(RepoSuccess, SchemaStub,
                     introspector: IntrospectorStub,
                     diff: DiffWithChangesStub,
                     sql_generator: SQLGeneratorStub,
                     rename_resolver: RenameResolverPassthroughStub,
                     sql_query_fun: fn _repo, sql ->
                       send(self(), {:sql_executed, sql})
                       :ok
                     end
                   )
        end)

      assert_received {:diff_called, [{:drop_table, :legacy_users}]}
      assert_received {:sql_generate_called, [{:drop_table, :legacy_users}]}
      assert_received :transaction_called

      assert_received {:sql_executed, "ALTER TABLE \"users\" ADD COLUMN \"email\" text;"}
      assert_received {:sql_executed, "DROP TABLE \"legacy_users\" CASCADE;"}

      assert log =~ "Applying changes..."
      assert log =~ "Executing:"
    end

    test "returns {:error, reason} when transaction fails" do
      assert {:error, :tx_failed} =
               Migrator.run(RepoError, SchemaStub,
                 introspector: IntrospectorStub,
                 diff: DiffWithChangesStub,
                 sql_generator: SQLGeneratorStub,
                 rename_resolver: RenameResolverPassthroughStub,
                 sql_query_fun: fn _repo, _sql ->
                   send(self(), :sql_query_called)
                   :ok
                 end
               )

      assert_received :transaction_called
      assert_received {:sql_generate_called, [{:drop_table, :legacy_users}]}
      refute_received :sql_query_called
    end

    test "returns {:error, :aborted} without executing when rename_resolver aborts" do
      assert {:error, :aborted} =
               Migrator.run(RepoSuccess, SchemaStub,
                 introspector: IntrospectorStub,
                 diff: DiffAmbiguousRenameStub,
                 sql_generator: SQLGeneratorStub,
                 rename_resolver: RenameResolverAbortStub,
                 sql_query_fun: fn _repo, _sql -> :ok end
               )

      refute_received {:sql_generate_called, _}
      refute_received :transaction_called
    end
  end
end
