defmodule PgPushex.Migrator do
  @type sql_query_fun :: (module(), String.t() -> term())

  @type run_opt ::
          {:introspector, module()}
          | {:diff, module()}
          | {:sql_generator, module()}
          | {:sql_query_fun, sql_query_fun()}
          | {:rename_resolver, module()}

  @type run_opts :: [run_opt()]

  @spec run(module(), module()) :: {:ok, :pushed | :no_changes} | {:error, term()}
  def run(repo, schema_module), do: run(repo, schema_module, [])

  @spec run(module(), module(), run_opts()) :: {:ok, :pushed | :no_changes} | {:error, term()}
  def run(repo, schema_module, opts) when is_list(opts) do
    deps = dependencies(opts)

    log("Calculating diff...", :cyan)

    desired_state = schema_module.__schema__()
    current_state = deps.introspector.introspect(repo)
    operations = deps.diff.compare(current_state, desired_state)

    case operations do
      [] ->
        log("No changes detected", :green)
        {:ok, :no_changes}

      _ ->
        case deps.rename_resolver.resolve_renames(operations) do
          {:ok, resolved_operations} ->
            log("Generating SQL...", :cyan)
            statements = deps.sql_generator.generate(resolved_operations)
            execute_statements(repo, statements, deps.sql_query_fun)

          :abort ->
            {:error, :aborted}
        end
    end
  end

  defp dependencies(opts) do
    %{
      introspector: Keyword.get(opts, :introspector, PgPushex.Introspector.Postgres),
      diff: Keyword.get(opts, :diff, PgPushex.Diff),
      sql_generator: Keyword.get(opts, :sql_generator, PgPushex.SQL.Postgres),
      sql_query_fun: Keyword.get(opts, :sql_query_fun, &default_sql_query/2),
      rename_resolver: Keyword.get(opts, :rename_resolver, PgPushex.CLI.Interactive)
    }
  end

  defp execute_statements(repo, sql_statements, sql_query_fun) do
    case repo.transaction(fn ->
           log("Applying changes...", :cyan)

           Enum.each(sql_statements, fn sql ->
             log("Executing: #{sql}", :light_black)
             sql_query_fun.(repo, sql)
           end)
         end) do
      {:ok, _result} ->
        {:ok, :pushed}

      {:error, reason} ->
        log("Error: #{inspect(reason)}", :red)
        {:error, reason}
    end
  end

  defp default_sql_query(repo, sql) do
    Ecto.Adapters.SQL.query!(repo, sql, [], log: false)
  end

  defp log(message, color) do
    IO.puts(IO.ANSI.format([color, message, :reset]))
  end
end
