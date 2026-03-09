# Migrating from Ecto Migrations

This guide helps you transition from traditional Ecto migrations to PgPushex's schema-first approach.

## Understanding the Differences

### Traditional Ecto Approach

```
lib/
  my_app/
    repo.ex
  
priv/
  repo/
    migrations/
      20240101120000_create_users.exs
      20240102130000_add_email_to_users.exs
      20240103140000_create_posts.exs
      20240104150000_add_user_id_to_posts.exs
      ... (hundreds of files over time)
```

**Problems:**
- Migration files accumulate endlessly
- Hard to see current schema at a glance
- Column renames are risky
- Dependencies between migrations can break

### PgPushex Approach

```
lib/
  my_app/
    schema.ex    # ← Single source of truth
    repo.ex
```

**Benefits:**
- Schema is always readable and complete
- Automatic diff calculation
- Safe column renames with interactive prompts
- No migration file accumulation

## Migration Strategies

### Strategy 1: Fresh Start (Recommended for New Projects)

If you're starting a new project:

1. Create your schema file with all desired tables
2. Create and push to a fresh database

```bash
# Drop and recreate database
dropdb myapp_dev
createdb myapp_dev

# Apply schema
mix pg_pushex.push -r MyApp.Repo -s MyApp.Schema
```

### Strategy 2: Adopt PgPushex on Existing Project

If you have existing Ecto migrations:

#### Step 1: Introspect Current Database

First, ensure your current database is up to date:

```bash
mix ecto.migrate
```

#### Step 2: Generate Initial Schema

Create `lib/my_app/schema.ex` by introspecting your database:

```elixir
defmodule MyApp.Schema do
  use PgPushex.Schema

  # Manually recreate your existing schema
  # Start with core tables, add foreign keys after
  
  table :users do
    column :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
    column :email, :string, null: false
    column :name, :string
    column :inserted_at, :utc_datetime, null: false
    column :updated_at, :utc_datetime, null: false
    
    index :users_email_index, [:email], unique: true
  end
  
  # ... other tables
end
```

**Tip:** Use `\d table_name` in psql to see current structure.

#### Step 3: Verify No Diff

```bash
mix pg_pushex.push -r MyApp.Repo -s MyApp.Schema
```

Expected output: `No changes detected`

If you see changes, adjust your schema file until they match.

#### Step 4: Update Team Workflow

Update your `README.md` or developer docs:

```markdown
## Database Schema

We use PgPushex for schema management.

### Making Schema Changes

1. Edit `lib/my_app/schema.ex`
2. Run `mix pg_pushex.push`

### New Developer Setup

```bash
mix deps.get
mix ecto.create
mix pg_pushex.push
```
```

## Translating Common Patterns

### Creating a Table

**Ecto:**
```elixir
# priv/repo/migrations/20240101120000_create_users.exs
defmodule MyApp.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :email, :string, null: false
      add :name, :string
      
      timestamps()
    end
    
    create unique_index(:users, [:email])
  end
end
```

**PgPushex:**
```elixir
# lib/my_app/schema.ex
table :users do
  column :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
  column :email, :string, null: false
  column :name, :string
  
  timestamps()
  
  index :users_email_index, [:email], unique: true
end
```

### Adding a Column

**Ecto:**
```elixir
# New migration file required
defmodule MyApp.Repo.Migrations.AddPhoneToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :phone, :string
    end
  end
end
```

**PgPushex:**
```elixir
# Just edit the existing table
table :users do
  column :id, :uuid, primary_key: true
  column :email, :string, null: false
  column :name, :string
  column :phone, :string  # ← Add here
  
  timestamps()
end
```

### Adding an Index

**Ecto:**
```elixir
defmodule MyApp.Repo.Migrations.AddIndexToUsersName do
  use Ecto.Migration

  def change do
    create index(:users, [:name])
  end
end
```

**PgPushex:**
```elixir
table :users do
  # ... columns ...
  
  index :users_name_index, [:name]  # ← Add here
end
```

### Foreign Keys

**Ecto:**
```elixir
defmodule MyApp.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :title, :string
      add :user_id, references(:users, on_delete: :delete_all)
      
      timestamps()
    end
  end
end
```

**PgPushex:**
```elixir
table :posts do
  column :id, :uuid, primary_key: true
  column :title, :string
  column :user_id, :uuid, references: :users, on_delete: :delete_all
  
  timestamps()
end
```

### Renaming a Column

**Ecto:**
```elixir
defmodule MyApp.Repo.Migrations.RenameEmailToEmailAddress do
  use Ecto.Migration

  def change do
    rename table(:users), :email, to: :email_address
  end
end
```

**PgPushex:**
```elixir
# 1. Change the column name
table :users do
  column :email_address, :string, null: false  # was :email
  # ...
end

# 2. PgPushex will detect and ask:
# "Rename email to email_address?"
# Choose option 2 to preserve data
```

### Custom SQL

**Ecto:**
```elixir
defmodule MyApp.Repo.Migrations.AddGinIndex do
  use Ecto.Migration

  def change do
    execute "CREATE INDEX CONCURRENTLY ON users USING GIN (data)"
  end
end
```

**PgPushex:**
```elixir
# Note: This runs EVERY push, so make it idempotent
table :users do
  # ... columns ...
end

execute "CREATE INDEX IF NOT EXISTS users_data_gin ON users USING GIN (data)"
```

## Hybrid Approach: Using Both Systems

You can use PgPushex alongside existing Ecto migrations during transition:

### Option 1: PgPushex Generates Migrations

```bash
# Generate migration instead of direct push
mix pg_pushex.generate -r MyApp.Repo -s MyApp.Schema

# Then use standard Ecto workflow
mix ecto.migrate
```

### Option 2: Gradual Migration

1. Keep existing migrations for history
2. Mark them as "completed" in your production database
3. Use PgPushex going forward

```elixir
# In your schema file, match production first
# Then evolve with PgPushex
```

## Handling Edge Cases

### Complex Migrations with Data Transformation

Sometimes you need to transform data during migration:

**Ecto way (still valid):**
```elixir
defmodule MyApp.Repo.Migrations.MigrateData do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :full_name, :string
    end
    
    execute "UPDATE users SET full_name = first_name || ' ' || last_name"
    
    alter table(:users) do
      remove :first_name
      remove :last_name
    end
  end
end
```

**PgPushex + manual script:**
```elixir
# schema.ex - define final state
table :users do
  column :full_name, :string
  # Note: no first_name or last_name
end

# Then run a separate data migration script
```

### Conditional Changes

**Ecto:**
```elixir
def change do
  if System.get_env("MIGRATE_PHONE") do
    alter table(:users) do
      add :phone, :string
    end
  end
end
```

**PgPushex:**
PgPushex doesn't support conditional schema definitions. Use multiple schema modules:

```elixir
# Base schema
defmodule MyApp.Schema.Base do
  use PgPushex.Schema
  
  table :users do
    column :id, :uuid, primary_key: true
    column :email, :string
  end
end

# Extended schema with optional features
defmodule MyApp.Schema.WithPhone do
  use PgPushex.Schema
  
  table :users do
    column :id, :uuid, primary_key: true
    column :email, :string
    column :phone, :string
  end
end
```

## Team Transition Checklist

- [ ] All developers install new dependency
- [ ] Document the new workflow
- [ ] Create initial schema from existing database
- [ ] Verify no diff on existing database
- [ ] Update CI/CD pipelines if needed
- [ ] Train team on interactive rename prompts
- [ ] Archive old migration conventions doc

## Common Questions

### "What happens to old migration files?"

Keep them! They're your history. New changes use PgPushex.

### "Can I go back to Ecto migrations?"

Yes. Use `mix pg_pushex.generate` to create migration files, then switch back.

### "How do I handle multiple environments?"

```elixir
# config/dev.exs
config :pg_pushex, schema: MyApp.DevSchema

# config/prod.exs
config :pg_pushex, schema: MyApp.ProdSchema
```

### "What about rollbacks?"

PgPushex doesn't have rollbacks like Ecto. To revert:
1. Restore schema file from git
2. Run `mix pg_pushex.push`

Or use `mix pg_pushex.generate` to see what would change.

## Summary

| Task | Ecto | PgPushex |
|------|------|----------|
| Create table | `mix ecto.gen.migration` + edit | Edit schema.ex |
| Add column | New migration | Edit schema.ex |
| Rename column | `rename/3` | Interactive prompt |
| Drop column | `remove/1` | Remove from schema.ex |
| Add index | `create index/2` | Add to schema.ex |
| See current schema | Check multiple files | Read schema.ex |
| Deploy changes | `mix ecto.migrate` | `mix pg_pushex.push` |

## Next Steps

- Read the [Schema DSL Reference](./schema_dsl.md)
- Learn [Advanced Patterns](./advanced_patterns.md)
- Check [Troubleshooting](../README.md#troubleshooting) if you hit issues
