ExUnit.start(exclude: [:integration])

test_repo_config = [
  hostname: "localhost",
  port: 5432,
  database: "pg_pushex_test",
  username: "postgres",
  password: "postgres",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10
]

Application.put_env(:pg_pushex, PgPushex.TestRepo, test_repo_config)

{:ok, _} = Application.ensure_all_started(:ecto_sql)
{:ok, _} = Application.ensure_all_started(:postgrex)

defmodule PgPushex.TestRepo do
  use Ecto.Repo,
    otp_app: :pg_pushex,
    adapter: Ecto.Adapters.Postgres
end

postgres_config = [
  hostname: "localhost",
  port: 5432,
  database: "postgres",
  username: "postgres",
  password: "postgres"
]

{:ok, conn} = Postgrex.start_link(postgres_config)

case Postgrex.query(conn, "SELECT 1 FROM pg_database WHERE datname = 'pg_pushex_test'", []) do
  {:ok, %{rows: []}} ->
    Postgrex.query!(conn, "CREATE DATABASE pg_pushex_test", [])
    IO.puts("Created database pg_pushex_test")

  {:ok, _} ->
    :ok
end

GenServer.stop(conn)

{:ok, _pid} = PgPushex.TestRepo.start_link()

Ecto.Adapters.SQL.Sandbox.mode(PgPushex.TestRepo, :manual)
