# PgPushex

> **Schema-first database migrations for PostgreSQL and Ecto**

PgPushex is a powerful Elixir library that revolutionizes how you manage database schema changes. Instead of writing manual migration files, you define your entire database schema using a clean, declarative Elixir DSL  and PgPushex handles the rest.

[![Hex.pm](https://img.shields.io/hexpm/v/pg_pushex.svg)](https://hex.pm/packages/pg_pushex)
[![Documentation](https://img.shields.io/badge/documentation-hexdocs-blue.svg)](https://hexdocs.pm/pg_pushex)

---

## Table of Contents

- [Why PgPushex?](#why-pg-pushex)
- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Defining Your Schema](#defining-your-schema)
- [Common Workflows](#common-workflows)
- [Column Types](#column-types)
- [Advanced Features](#advanced-features)
- [Configuration](#configuration)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

### The PgPushex Solution

With PgPushex, you:
1. **Define your schema once**  in a single, readable Elixir module
2. **Run one command**  to apply all changes
3. **Get intelligent diffs**  PgPushex calculates exactly what needs to change
4. **Enjoy safety**  all changes run in a transaction
5. **Handle renames interactively**  never accidentally lose data

---

## Features

- **Declarative DSL** Define tables, columns, indexes in clean Elixir code
- **Automatic Diff Calculation**  Compares desired vs current state
- **Interactive Rename Detection**  Smart prompts when columns change
- **Transaction Safety**  All changes are atomic
- **PostgreSQL Native**  Full support for PG-specific features
- **Foreign Key Handling**  Automatic dependency ordering
- **Generated Columns**  Native support for computed columns
- **Enum Types**  PostgreSQL ENUM support
- **Extensions**  Easy pgvector, citext, and other extensions
- **Migration Generation**  Optional Ecto migration file output

---

## Installation

Add `pg_pushex` to your `mix.exs`:

```elixir
def deps do
  [
    {:pg_pushex, "~> 0.1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

### Requirements

- Elixir ~> 1.15
- PostgreSQL 12+
- Ecto ~> 3.10

---

## Quick Start

### 1. Create Your Schema Module

Create `lib/my_app/schema.ex`:

```elixir
defmodule MyApp.Schema do
  use PgPushex.Schema

  # Define tables
  table :users do
    column :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
    column :email, :string, size: 255, null: false
    column :name, :string
    column :is_active, :boolean, default: true
    
    timestamps(type: :utc_datetime)
    
    index :users_email_index, [:email], unique: true
  end

  table :posts do
    column :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
    column :title, :string, null: false
    column :body, :text
    column :published_at, :utc_datetime
    column :user_id, :uuid, references: :users, on_delete: :delete_all
    
    timestamps(type: :utc_datetime)
    
    index :posts_user_id_index, [:user_id]
    index :posts_published_index, [:published_at]
  end
end
```

### 2. Configure

In `config/config.exs`:

```elixir
import Config

config :my_app,
  ecto_repos: [MyApp.Repo]

config :my_app, MyApp.Repo,
  username: "postgres",
  password: "postgres",
  database: "my_app_dev",
  hostname: "localhost",
  port: 5432,
  pool_size: 10

config :pg_pushex,
  repo: MyApp.Repo,
  schema: MyApp.Schema
```

### 3. Apply to Database

```bash
# Push schema directly to database
mix pg_pushex.push

# Or generate an Ecto migration file
mix pg_pushex.generate
```

You can also pass repo and schema explicitly (overrides config):

```bash
mix pg_pushex.push -r MyApp.Repo -s MyApp.Schema
```

---

## Defining Your Schema

### Basic Table Definition

```elixir
table :products do
  column :id, :uuid, primary_key: true
  column :name, :string, null: false
  column :description, :text
  column :price, :decimal
  column :in_stock, :boolean, default: true
  column :sku, :string, size: 50
  
  timestamps()
end
```

### Column Options

| Option | Type | Description | Example |
|--------|------|-------------|---------|
| `:null` | boolean | Allow NULL values | `null: false` |
| `:default` | any | Default value | `default: "pending"` |
| `:primary_key` | boolean | Mark as primary key | `primary_key: true` |
| `:references` | atom | Foreign key reference | `references: :users` |
| `:referenced_column` | atom | FK reference column (default: `:id`) | `referenced_column: :email` |
| `:on_delete` | atom | FK delete action | `on_delete: :delete_all` |
| `:on_update` | atom | FK update action | `on_update: :update_all` |
| `:size` | integer | String/vector size | `size: 255` |
| `:enum` | list | Enum values | `enum: ["a", "b"]` |
| `:generated_as` | fragment | Computed column | `generated_as: fragment("...")` |

### Indexes

```elixir
table :orders do
  column :id, :uuid, primary_key: true
  column :status, :string
  column :user_id, :uuid
  column :total, :decimal
  
  # Regular index
  index :orders_status_index, [:status]
  
  # Unique index
  index :orders_user_total_index, [:user_id, :total], unique: true
  
  # Convenience macro for unique indexes
  unique_index :orders_number_unique, [:order_number]
end
```

### Foreign Keys

```elixir
table :comments do
  column :id, :uuid, primary_key: true
  column :body, :text

  # Simple FK
  column :post_id, :uuid, references: :posts

  # FK with cascade delete
  column :author_id, :uuid, references: :users, on_delete: :delete_all

  # FK with custom actions
  column :editor_id, :uuid,
    references: :users,
    on_delete: :nilify_all,
    on_update: :restrict

  # FK referencing a non-primary key column (must be UNIQUE)
  column :user_email, :string, references: :users, referenced_column: :email
end
```

> **Note:** Changing `on_delete`/`on_update` on an **existing** FK constraint is not currently supported. PgPushex does not track constraint names, so altering FK actions requires a manual `DROP CONSTRAINT` + `ADD CONSTRAINT`. This only affects schema changes — initial FK creation works correctly.

### Timestamps

```elixir
table :articles do
  # Default timestamps (inserted_at, updated_at)
  timestamps()
  
  # Custom type
  timestamps(type: :naive_datetime)
  
  # Partial timestamps
  timestamps(inserted_at: true, updated_at: false)
end
```

### PostgreSQL Extensions

```elixir
defmodule MyApp.Schema do
  use PgPushex.Schema

  # Explicitly declare extensions
  extension "uuid-ossp"
  extension "vector"
  
  # Or they are auto-inferred from column types
  table :documents do
    column :id, :uuid, primary_key: true
    column :content_vector, :vector, size: 1536  # auto-adds "vector" extension
    column :title, :citext                       # auto-adds "citext" extension
  end
end
```

### Custom SQL

> **Warning:** SQL passed to `execute/1` is executed on **every** `mix pg_pushex.push`, regardless of whether the database is already in sync. Make sure your SQL is idempotent (safe to run multiple times).

> **Note:** All `execute/1` statements run **before** table creations and modifications — they cannot reference tables that are being created in the same push.

```elixir
defmodule MyApp.Schema do
  use PgPushex.Schema

  # Runs before any table operations on every push — must be idempotent
  execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\""
  
  table :events do
    column :id, :uuid, primary_key: true
    column :data, :map
  end
end
```

---

## Common Workflows

### First Time Setup

```bash
# Generate a full migration (no DB connection needed)
mix pg_pushex.generate.full -r MyApp.Repo -s MyApp.Schema

# Or push directly
dropdb myapp_dev && createdb myapp_dev
mix pg_pushex.push -r MyApp.Repo -s MyApp.Schema
```

### Making Schema Changes

1. **Edit your schema file** (add/modify columns, tables, etc.)
2. **Review changes**:
   ```bash
   mix pg_pushex.generate -r MyApp.Repo -s MyApp.Schema
   # Review the generated migration file
   ```
3. **Apply changes**:
   ```bash
   mix pg_pushex.push -r MyApp.Repo -s MyApp.Schema
   ```

### Column Renames (Interactive)

When PgPushex detects a column drop + add in the same table:

```
Column changes detected in table :users

  Dropped: email (:string)
  Added:   email_address (:string)

How would you like to proceed?

  1. Drop old columns and create new ones (DATA LOSS)
  2. Rename email to email_address
  3. Abort

Enter choice: 2
```

### Reset Database (Development)

⚠️ **DESTRUCTIVE - ALL DATA LOST**

```bash
mix pg_pushex.reset -r MyApp.Repo
```

> **Note:** `reset` drops and recreates the database, then runs `mix pg_pushex.push`. The schema module is taken from `config :pg_pushex, schema:` — the `-s` flag has no effect on this task.

---

## Column Types

### Basic Types

| Type | PostgreSQL | Notes |
|------|------------|-------|
| `:string` | VARCHAR/TEXT | Use `size:` for VARCHAR |
| `:text` | TEXT | Unlimited length |
| `:integer` | INTEGER | 32-bit |
| `:bigint` | BIGINT | 64-bit |
| `:serial` | SERIAL | Auto-increment |
| `:bigserial` | BIGSERIAL | 64-bit auto-increment |
| `:smallint` | SMALLINT | 16-bit |
| `:uuid` | UUID | Use with `gen_random_uuid()` |
| `:boolean` | BOOLEAN | true/false |
| `:float` | DOUBLE PRECISION | 64-bit float |
| `:decimal` | NUMERIC | Exact precision |
| `:date` | DATE | Calendar date |
| `:time` | TIME | Time of day |
| `:naive_datetime` | TIMESTAMP | Without timezone |
| `:utc_datetime` | TIMESTAMPTZ | With timezone (recommended) |
| `:binary` | BYTEA | Binary data |
| `:map` | JSONB | JSON storage |

### PostgreSQL-Specific Types

| Type | Extension | Example |
|------|-----------|---------|
| `:vector` | pgvector | `column :embedding, :vector, size: 1536` |
| `:tsvector` | built-in | Full-text search |
| `:citext` | citext | Case-insensitive text |

> **Known limitation:** `:citext` and `:tsvector` columns are accepted by the DSL and created correctly, but they are **not read back** during database introspection. This causes a perpetual diff — PgPushex will attempt to re-add these columns on every push. Avoid using these types in tables that are pushed repeatedly until this is resolved.

### Enums

```elixir
table :tasks do
  column :status, :string, enum: ["pending", "running", "completed", "failed"]
  column :priority, :string, enum: ["low", "medium", "high"], default: "medium"
end
```

---

## Advanced Features

### Generated Columns

```elixir
table :users do
  column :first_name, :string
  column :last_name, :string
  
  # Computed column (stored)
  column :full_name, :string, 
    generated_as: fragment("first_name || ' ' || last_name")
end
```

### Fragments

Use `fragment/1` for PostgreSQL-specific expressions:

```elixir
table :items do
  # UUID generation
  column :id, :uuid, primary_key: true, 
    default: fragment("gen_random_uuid()")
  
  # Current timestamp
  column :created_at, :utc_datetime, 
    default: fragment("NOW()")
  
  # Complex default
  column :slug, :string, 
    default: fragment("LOWER(REPLACE(name, ' ', '-'))")
end
```

### Multiple Schemas

```elixir
# lib/my_app/analytics_schema.ex
defmodule MyApp.AnalyticsSchema do
  use PgPushex.Schema
  
  table :events do
    column :id, :uuid, primary_key: true
    column :name, :string
    column :properties, :map
    timestamps()
  end
end

# Apply specific schema
mix pg_pushex.push -r MyApp.Repo -s MyApp.AnalyticsSchema
```

---

## Configuration

### Application Config

```elixir
# config/config.exs
config :pg_pushex,
  repo: MyApp.Repo,
  schema: MyApp.Schema

# Then you can run without -r and -s flags:
mix pg_pushex.push
```

### Per-Environment Schemas

```elixir
# config/dev.exs
config :pg_pushex,
  schema: MyApp.DevSchema

# config/test.exs
config :pg_pushex,
  schema: MyApp.TestSchema
```

---

## Best Practices

### 1. Keep Schema Files Organized

```
lib/
  my_app/
    schema/
      core_schema.ex      # Users, accounts
      analytics_schema.ex # Events, metrics
      content_schema.ex   # Posts, comments
```

### 2. Use UUIDs for Primary Keys

```elixir
table :orders do
  column :id, :uuid, primary_key: true, 
    default: fragment("gen_random_uuid()")
end
```

### 3. Always Add Timestamps

```elixir
table :records do
  # ... columns ...
  timestamps(type: :utc_datetime)
end
```

### 4. Index Foreign Keys

```elixir
table :comments do
  column :post_id, :uuid, references: :posts
  index :comments_post_id_index, [:post_id]  # Add this!
end
```

### 5. Review Before Pushing

```bash
# Generate migration first to review
mix pg_pushex.generate -r MyApp.Repo -s MyApp.Schema

# Check the generated file, then push
mix pg_pushex.push -r MyApp.Repo -s MyApp.Schema
```

---

## Troubleshooting

### Error: "relation does not exist"

Ensure you've created the database:

```bash
mix ecto.create
```

### Error: "extension not found"

Install the required PostgreSQL extension:

```bash
# For pgvector
psql -d myapp_dev -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

### Column rename not detected

PgPushex only detects renames when both of these are true:
- A column is dropped AND
- A column is added in the **same table** in the same push

Both conditions must occur together. If you only add or only remove a column, no rename prompt is shown. Column types do not affect whether a rename is suggested — any dropped+added pair in the same table triggers the interactive prompt.

### Reset stuck in transaction

If a push fails, the transaction is rolled back automatically. If something seems stuck:

```bash
# Check for locks
psql -d myapp_dev -c "SELECT * FROM pg_locks WHERE NOT granted;"
```

---

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request

---

## License

MIT License - see [LICENSE](./LICENSE) file for details.

---

## Credits

Created with ❤️ for the Elixir community.

For detailed API documentation, visit [HexDocs](https://hexdocs.pm/pg_pushex).
