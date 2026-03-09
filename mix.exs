defmodule PgPushex.MixProject do
  use Mix.Project

  @source_url "https://github.com/tachyon322/pg_pushex"
  @version "0.1.0"

  def project do
    [
      app: :pg_pushex,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      name: "PgPushex",
      description: "Schema-first database migration tool for PostgreSQL and Ecto",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {PgPushex.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto_sql, "~> 3.10"},
      {:postgrex, "~> 0.17"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      description: "Schema-first database migration tool for PostgreSQL and Ecto",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      maintainers: ["Denis Cheremnykh"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "guides/getting_started.md",
        "guides/schema_dsl.md",
        "guides/advanced_patterns.md",
        "guides/migrating_from_ecto.md"
      ],
      groups_for_extras: [
        Introduction: ["README.md"],
        Guides: [
          "guides/getting_started.md",
          "guides/schema_dsl.md",
          "guides/advanced_patterns.md",
          "guides/migrating_from_ecto.md"
        ],
        Changelog: ["CHANGELOG.md"]
      ],
      groups_for_modules: [
        Core: [
          PgPushex,
          PgPushex.Schema,
          PgPushex.Migrator
        ],
        "Diff & Generation": [
          PgPushex.Diff,
          PgPushex.MigrationGenerator
        ],
        Introspection: [
          PgPushex.Introspector.Postgres
        ],
        "SQL Generation": [
          PgPushex.SQL.Postgres
        ],
        State: [
          PgPushex.State.Schema,
          PgPushex.State.Table,
          PgPushex.State.Column,
          PgPushex.State.Index,
          PgPushex.State.ForeignKey
        ],
        CLI: [
          PgPushex.CLI.Helpers,
          PgPushex.CLI.Interactive
        ],
        "Mix Tasks": [
          Mix.Tasks.PgPushex.Push,
          Mix.Tasks.PgPushex.Generate,
          Mix.Tasks.PgPushex.Generate.Full,
          Mix.Tasks.PgPushex.Reset
        ]
      ]
    ]
  end
end
