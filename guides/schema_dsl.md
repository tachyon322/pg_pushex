# Schema DSL Reference

This guide provides comprehensive documentation for PgPushex's Domain Specific Language (DSL) for defining database schemas.

## Overview

The PgPushex DSL is designed to be:
- **Declarative**: Describe what you want, not how to get there
- **Familiar**: Similar to Ecto's schema DSL
- **PostgreSQL-native**: Full access to PG-specific features

## Module Setup

Every schema module starts with:

```elixir
defmodule MyApp.Schema do
  use PgPushex.Schema
  
  # Your definitions here...
end
```

The `use PgPushex.Schema` line imports all the DSL macros and sets up the module.

## Extensions

### `extension/1`

Declares PostgreSQL extensions that should be installed.

```elixir
extension "uuid-ossp"
extension "vector"
extension "citext"
```

**Notes:**
- Extensions are created with `CREATE EXTENSION IF NOT EXISTS`
- Some extensions (like `vector` and `citext`) are auto-inferred from column types
- Extensions are created before any tables

## Tables

### `table/2`

Defines a database table.

```elixir
table :users do
  # columns and indexes
end
```

**Options:**
None currently supported (primary key handling is done at column level)

**Example with all features:**

```elixir
table :products do
  column :id, :uuid, primary_key: true
  column :name, :string, null: false
  column :price, :decimal
  
  timestamps()
  
  index :products_name_index, [:name]
end
```

## Columns

### `column/3`

Defines a column within a table.

```elixir
column :name, :string
column :name, :type, option: value
```

**Parameters:**
- `name` (atom) — Column name
- `type` (atom) — Data type
- `opts` (keyword) — Optional column options

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:null` | boolean | `true` | Allow NULL values (false for PK) |
| `:default` | any | `nil` | Default value or `fragment/1` |
| `:primary_key` | boolean | `false` | Mark as primary key |
| `:references` | atom | `nil` | Foreign key reference table |
| `:on_delete` | atom | `:nothing` | FK delete action |
| `:on_update` | atom | `:nothing` | FK update action |
| `:size` | integer | `nil` | Size for string/vector |
| `:enum` | [String.t()] | `nil` | Enum values |
| `:generated_as` | fragment | `nil` | Computed column expression |

### Basic Column Examples

```elixir
# Simple column
column :name, :string

# Non-nullable
column :email, :string, null: false

# With default
column :status, :string, default: "pending"
column :count, :integer, default: 0
column :is_active, :boolean, default: true

# Sized string
column :sku, :string, size: 50

# UUID primary key
column :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
```

### Foreign Key Columns

```elixir
# Simple foreign key
column :user_id, :uuid, references: :users

# With cascade delete
column :post_id, :uuid, references: :posts, on_delete: :delete_all

# With custom actions
column :author_id, :uuid, 
  references: :users,
  on_delete: :nilify_all,
  on_update: :update_all
```

**Foreign Key Actions:**

| Action | SQL | Description |
|--------|-----|-------------|
| `:nothing` | (none) | No action (default) |
| `:delete_all` | ON DELETE CASCADE | Delete referencing rows |
| `:nilify_all` | ON DELETE SET NULL | Set FK column to NULL |
| `:restrict` | ON DELETE/UPDATE RESTRICT | Prevent the operation |
| `:update_all` | ON UPDATE CASCADE | Cascade updates to referencing rows |

> **Note:** Only these exact atoms are valid in the DSL. `:cascade` and `:set_null` are not accepted — use `:delete_all` and `:nilify_all` instead.

### Enum Columns

```elixir
column :status, :string, enum: ["draft", "published", "archived"]
column :priority, :string, enum: ["low", "medium", "high"], default: "medium"
```

This creates a PostgreSQL ENUM type named `{table}_{column}_enum`.

### Generated Columns

```elixir
# Computed from other columns
column :full_name, :string,
  generated_as: fragment("first_name || ' ' || last_name")
```

**Important:** Generated columns:
- Cannot have a `:default` value
- Are always STORED (not virtual)
- Can be indexed like regular columns

> **Note:** Avoid using `:tsvector` as the type for generated columns. Due to a known introspection limitation, `:tsvector` columns are not read back correctly from the database, which causes a perpetual diff on every push.

## Timestamps

### `timestamps/1`

Adds `inserted_at` and `updated_at` columns automatically.

```elixir
timestamps()                           # Default UTC datetime
timestamps(type: :naive_datetime)      # Without timezone
timestamps(inserted_at: false)         # Only updated_at
timestamps(updated_at: false)          # Only inserted_at
```

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:type` | atom | `:utc_datetime` | Timestamp type |
| `:inserted_at` | boolean | `true` | Include inserted_at |
| `:updated_at` | boolean | `true` | Include updated_at |

Both columns are created as `NOT NULL` with no default.

## Indexes

### `index/3`

Creates an index on the table.

```elixir
index :name, [:column1, :column2], unique: true
```

**Parameters:**
- `name` (atom) — Index name
- `columns` (list of atoms) — Column names to index
- `opts` (keyword) — Options

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:unique` | boolean | `false` | Create unique index |

### `unique_index/2`

Convenience macro for unique indexes.

```elixir
unique_index :users_email_unique, [:email]
# Equivalent to:
index :users_email_unique, [:email], unique: true
```

### Index Examples

```elixir
table :products do
  # Single column index
  index :products_name_index, [:name]
  
  # Multi-column index
  index :products_category_price_index, [:category_id, :price]
  
  # Unique index
  index :products_sku_unique, [:sku], unique: true
  
  # Using convenience macro
  unique_index :products_code_unique, [:product_code]
end
```

## Raw SQL

### `execute/1`

Execute arbitrary SQL during schema push.

```elixir
execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\""
execute "CREATE INDEX CONCURRENTLY my_index ON users USING GIN (data)"
```

**⚠️ Warning:** SQL in `execute/1` runs on **every** push, not just when needed. Ensure your SQL is idempotent.

**⚠️ Order:** All `execute/1` statements run **before** any table creations or modifications. They cannot reference tables that are being created in the same push.

### `fragment/1`

Creates a SQL fragment for use in defaults or generated columns.

```elixir
column :id, :uuid, default: fragment("gen_random_uuid()")
column :total, :decimal, generated_as: fragment("price * quantity")
```

## Complete Example

Here's a comprehensive example showcasing all DSL features:

```elixir
defmodule MyApp.CompleteSchema do
  use PgPushex.Schema

  # Extensions
  extension "uuid-ossp"
  extension "vector"

  # Raw SQL (runs every time)
  execute "SET timezone TO 'UTC'"

  # Users table
  table :users do
    column :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
    column :email, :string, null: false  # use :citext only if aware of known limitation (see below)
    column :name, :string, null: false
    column :settings, :map  # map defaults are not supported — omit default for :map columns
    
    timestamps()
    
    unique_index :users_email_unique, [:email]
  end

  # Posts table with FK
  table :posts do
    column :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
    column :title, :string, size: 200, null: false
    column :slug, :string, size: 200, null: false
    column :body, :text
    column :status, :string, enum: ["draft", "published", "archived"], default: "draft"
    column :published_at, :utc_datetime
    column :word_count, :integer, generated_as: fragment("array_length(regexp_split_to_array(body, '\&s+'), 1)")
    column :author_id, :uuid, references: :users, on_delete: :restrict
    
    timestamps()
    
    index :posts_slug_index, [:slug], unique: true
    index :posts_author_status_index, [:author_id, :status]
    index :posts_published_index, [:published_at]
  end

  # Embeddings for AI features
  table :document_embeddings do
    column :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
    column :document_id, :uuid, references: :posts, on_delete: :delete_all
    column :embedding, :vector, size: 1536, null: false
    column :model, :string, default: "text-embedding-3-small"
    
    timestamps(updated_at: false)
    
    index :embeddings_document_index, [:document_id]
  end
end
```

## Type Reference

### Basic Types

| DSL Type | PostgreSQL Type | Notes |
|----------|----------------|-------|
| `:string` | VARCHAR/TEXT | Use `size:` for VARCHAR |
| `:text` | TEXT | Unlimited length |
| `:integer` | INTEGER | 32-bit signed |
| `:bigint` | BIGINT | 64-bit signed |
| `:serial` | SERIAL | Auto-increment 32-bit |
| `:bigserial` | BIGSERIAL | Auto-increment 64-bit |
| `:smallint` | SMALLINT | 16-bit signed |
| `:uuid` | UUID | 128-bit identifier |
| `:boolean` | BOOLEAN | true/false |
| `:float` | DOUBLE PRECISION | 64-bit float |
| `:decimal` | NUMERIC | Arbitrary precision |
| `:date` | DATE | Calendar date |
| `:time` | TIME WITHOUT TIME ZONE | Time of day |
| `:naive_datetime` | TIMESTAMP WITHOUT TIME ZONE | No timezone |
| `:utc_datetime` | TIMESTAMP WITH TIME ZONE | UTC timezone |
| `:binary` | BYTEA | Binary data |
| `:map` | JSONB | Binary JSON |

### PostgreSQL-Specific Types

| DSL Type | Extension | Description |
|----------|-----------|-------------|
| `:vector` | pgvector | Vector embeddings |
| `:tsvector` | built-in | Full-text search vector |
| `:citext` | citext | Case-insensitive text |

> **Known limitation:** `:citext` and `:tsvector` columns are created correctly on first push, but are **not read back** during database introspection. This causes a perpetual diff — PgPushex will attempt to re-add these columns on every subsequent push. Avoid using them in actively-pushed tables until this is resolved.

### Type Aliases

These types are interchangeable:

- `:int` → `:integer`
- `:bool` → `:boolean`
- `:binary_id` → `:binary`

## Validation and Errors

PgPushex validates your schema at compile time:

```elixir
# ❌ Error: column outside table
column :name, :string  # Compilation error!

# ❌ Error: invalid type
table :users do
  column :age, :intiger  # Compilation error! (did you mean :integer?)
end

# ❌ Error: duplicate column names
table :users do
  column :name, :string
  column :name, :string  # Compilation error!
end

# ❌ Error: nested tables
table :users do
  table :posts do  # Compilation error!
    # ...
  end
end
```

## Best Practices

1. **Use UUIDs for primary keys** — Better for distributed systems
2. **Always add timestamps** — Essential for debugging
3. **Index foreign keys** — Improves join performance
4. **Use explicit size for strings** — When you know the limit
5. **Use enums for fixed values** — Better than CHECK constraints
6. **Keep fragments simple** — Complex SQL is harder to maintain

## Next Steps

- Learn about [workflow patterns](./advanced_patterns.md)
- See [migration strategies](./migrating_from_ecto.md)
- Read the [Getting Started guide](./getting_started.md)
