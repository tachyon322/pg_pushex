# Advanced Patterns

This guide covers advanced usage patterns, best practices, and complex scenarios for PgPushex.

## Table of Contents

- [Multi-Schema Applications](#multi-schema-applications)
- [Soft Deletes](#soft-deletes)
- [Tenant Isolation (Multi-tenancy)](#tenant-isolation-multi-tenancy)
- [Versioning and Auditing](#versioning-and-auditing)
- [Search and Full-text](#search-and-full-text)
- [Performance Optimization](#performance-optimization)
- [Handling Schema Drift](#handling-schema-drift)
- [CI/CD Integration](#cicd-integration)

## Multi-Schema Applications

Organize large applications into multiple schema modules:

```elixir
# lib/my_app/schema/identity.ex
defmodule MyApp.Schema.Identity do
  use PgPushex.Schema

  table :users do
    column :id, :uuid, primary_key: true
    column :email, :string, null: false
    column :password_hash, :string, null: false
    
    timestamps()
    
    unique_index :users_email_unique, [:email]
  end

  table :sessions do
    column :id, :uuid, primary_key: true
    column :user_id, :uuid, references: :users, on_delete: :delete_all
    column :token, :string, null: false
    column :expires_at, :utc_datetime, null: false
    
    timestamps(updated_at: false)
    
    index :sessions_user_index, [:user_id]
    index :sessions_token_index, [:token], unique: true
  end
end

# lib/my_app/schema/content.ex
defmodule MyApp.Schema.Content do
  use PgPushex.Schema

  table :posts do
    column :id, :uuid, primary_key: true
    column :title, :string, null: false
    column :body, :text
    column :status, :string, enum: ["draft", "published"], default: "draft"
    column :author_id, :uuid, references: :users, on_delete: :restrict
    
    timestamps()
    
    index :posts_author_index, [:author_id]
    index :posts_status_index, [:status]
  end

  table :comments do
    column :id, :uuid, primary_key: true
    column :body, :text, null: false
    column :post_id, :uuid, references: :posts, on_delete: :delete_all
    column :author_id, :uuid, references: :users, on_delete: :delete_all
    
    timestamps()
    
    index :comments_post_index, [:post_id]
  end
end
```

Apply individually:

```bash
mix pg_pushex.push -r MyApp.Repo -s MyApp.Schema.Identity
mix pg_pushex.push -r MyApp.Repo -s MyApp.Schema.Content
```

## Soft Deletes

Implement soft deletes with a deleted_at column:

```elixir
table :posts do
  column :id, :uuid, primary_key: true
  column :title, :string, null: false
  column :body, :text
  column :deleted_at, :utc_datetime  # NULL = not deleted
  
  timestamps()
  
  index :posts_active_index, [:deleted_at], unique: false
end
```

Add a partial index for better performance:

```elixir
execute """
CREATE INDEX posts_not_deleted_index ON posts (id) 
WHERE deleted_at IS NULL
"""
```

## Tenant Isolation (Multi-tenancy)

### Row-level Security Approach

```elixir
table :projects do
  column :id, :uuid, primary_key: true
  column :tenant_id, :uuid, null: false
  column :name, :string, null: false
  
  timestamps()
  
  index :projects_tenant_index, [:tenant_id]
end

table :tasks do
  column :id, :uuid, primary_key: true
  column :tenant_id, :uuid, null: false
  column :project_id, :uuid, references: :projects, on_delete: :delete_all
  column :title, :string, null: false
  
  timestamps()
  
  index :tasks_tenant_project_index, [:tenant_id, :project_id]
end

# Enable RLS
execute "ALTER TABLE projects ENABLE ROW LEVEL SECURITY"
execute "ALTER TABLE tasks ENABLE ROW LEVEL SECURITY"

# Create policies
execute "CREATE POLICY tenant_isolation_projects ON projects USING (tenant_id = current_setting('app.current_tenant')::uuid)"
```

## Versioning and Auditing

Create audit tables:

```elixir
table :users do
  column :id, :uuid, primary_key: true
  column :email, :string, null: false
  column :name, :string
  
  timestamps()
end

table :users_audit_log do
  column :id, :uuid, primary_key: true
  column :record_id, :uuid, null: false
  column :action, :string, null: false
  column :old_data, :map
  column :new_data, :map
  column :changed_by, :uuid
  column :changed_at, :utc_datetime, default: fragment("NOW()")
  
  index :users_audit_record_index, [:record_id]
end
```

## Search and Full-text

### Basic Full-text Search

```elixir
extension "uuid-ossp"

table :documents do
  column :id, :uuid, primary_key: true
  column :title, :string, null: false
  column :content, :text, null: false
  
  column :search_vector, :tsvector,
    generated_as: fragment("to_tsvector('english', coalesce(title, '') || ' ' || coalesce(content, ''))")
  
  timestamps()
end

execute "CREATE INDEX documents_search_index ON documents USING GIN (search_vector)"
```

## Performance Optimization

### Strategic Indexing

```elixir
table :orders do
  column :id, :uuid, primary_key: true
  column :user_id, :uuid, null: false
  column :status, :string, null: false
  column :created_at, :utc_datetime, null: false
  column :total, :decimal, null: false
  
  timestamps()
  
  # Covering index
  index :orders_user_status_created_index, [:user_id, :status, :created_at]
end

# Partial index
execute "CREATE INDEX orders_pending_index ON orders (created_at) WHERE status = 'pending'"
```

### Partitioning Preparation

```elixir
table :events do
  column :id, :uuid, primary_key: true
  column :occurred_at, :utc_datetime, null: false
  column :type, :string, null: false
  column :data, :map
  
  timestamps()
  
  index :events_occurred_index, [:occurred_at]
end
```

## Handling Schema Drift

### Detection

```bash
mix pg_pushex.generate -r MyApp.Repo -s MyApp.Schema
```

### Recovery Strategies

1. **Backport changes to schema:**
   ```elixir
   PgPushex.Introspector.Postgres.introspect(MyApp.Repo)
   ```

2. **Use generate to create migration:**
   ```bash
   mix pg_pushex.generate -r MyApp.Repo -s MyApp.Schema
   mix ecto.migrate
   ```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Database Schema Check

on:
  pull_request:
    paths:
      - 'lib/**/schema*.ex'

jobs:
  schema-check:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
        ports:
          - 5432:5432

    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.19'
          otp-version: '27'
      
      - name: Install dependencies
        run: mix deps.get
      
      - name: Create database
        run: mix ecto.create
      
      - name: Check schema can be applied
        run: mix pg_pushex.push -r MyApp.Repo -s MyApp.Schema
```

## Testing Patterns

### Isolated Test Schemas

```elixir
# test/support/test_schema.ex
defmodule MyApp.TestSchema do
  use PgPushex.Schema

  table :test_users do
    column :id, :uuid, primary_key: true
    column :email, :string
    timestamps()
  end
end
```

### Schema Validation Tests

```elixir
defmodule MyApp.SchemaValidationTest do
  use ExUnit.Case

  test "schema compiles without errors" do
    assert Code.ensure_loaded?(MyApp.Schema)
  end

  test "schema produces valid structure" do
    schema = MyApp.Schema.__schema__()
    assert map_size(schema.tables) > 0
    
    for {name, table} <- schema.tables do
      assert is_atom(name)
      assert length(table.columns) > 0
      assert Enum.any?(table.columns, & &1.primary_key)
    end
  end
end
```

## Best Practices Summary

1. **Version Control**: Commit schema files and tag releases
2. **Review Process**: Require PR review for schema changes
3. **Naming**: Use singular table names, descriptive indexes
4. **Safety**: Backup before changes, test in staging

## See Also

- [Getting Started](./getting_started.md)
- [Schema DSL Reference](./schema_dsl.md)
- [Migrating from Ecto](./migrating_from_ecto.md)
