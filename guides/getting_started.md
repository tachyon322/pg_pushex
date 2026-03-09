# Getting Started with PgPushex

This guide will walk you through setting up PgPushex in your Elixir application from scratch. By the end, you'll have a working schema that can be applied to your PostgreSQL database.

## Prerequisites

Before you begin, ensure you have:

- Elixir 1.15 or later installed
- PostgreSQL 12 or later running
- A working Ecto repository in your project
- Basic familiarity with Elixir and Ecto

## Step 1: Add PgPushex to Your Project

Add the dependency to your `mix.exs`:

```elixir
defp deps do
  [
    {:pg_pushex, "~> 0.1.0"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Step 2: Create Your First Schema

Create a new file at `lib/my_app/schema.ex`. Replace `MyApp` with your actual application name:

```elixir
defmodule MyApp.Schema do
  use PgPushex.Schema

  # Declare required PostgreSQL extensions
  extension "uuid-ossp"

  # Define your first table
  table :users do
    # Primary key using UUID
    column :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
    
    # User information
    column :email, :string, size: 255, null: false
    column :name, :string
    column :is_active, :boolean, default: true
    
    # Automatic timestamp columns
    timestamps(type: :utc_datetime)
    
    # Ensure email uniqueness
    index :users_email_index, [:email], unique: true
  end
end
```

## Step 3: Configure PgPushex (Optional but Recommended)

Add default configuration to `config/config.exs`:

```elixir
config :pg_pushex,
  repo: MyApp.Repo,
  schema: MyApp.Schema
```

This allows you to run commands without specifying `-r` and `-s` flags every time.

## Step 4: Create Your Database

If you haven't already, create your database:

```bash
mix ecto.create
```

## Step 5: Apply Your Schema

Now comes the exciting part — applying your schema to the database:

```bash
mix pg_pushex.push
```

If you didn't set up the configuration, use:

```bash
mix pg_pushex.push -r MyApp.Repo -s MyApp.Schema
```

You should see output like:

```
Calculating diff...
Applying changes...
Executing: CREATE EXTENSION IF NOT EXISTS "uuid-ossp"
Executing: CREATE TABLE "users" ("id" uuid PRIMARY KEY DEFAULT gen_random_uuid(), "email" varchar(255) NOT NULL, "name" text, "is_active" boolean DEFAULT TRUE, "inserted_at" timestamp with time zone NOT NULL, "updated_at" timestamp with time zone NOT NULL)
Executing: CREATE UNIQUE INDEX "users_email_index" ON "users" ("email")
Push successful!
```

🎉 Congratulations! Your schema has been applied to the database.

## Step 6: Verify the Results

You can verify the table was created:

```bash
psql -d your_database_name -c "\d users"
```

You should see all the columns we defined.

## Step 7: Make Your First Schema Change

Let's add a new table to see how schema evolution works. Edit `lib/my_app/schema.ex`:

```elixir
defmodule MyApp.Schema do
  use PgPushex.Schema

  extension "uuid-ossp"

  table :users do
    column :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
    column :email, :string, size: 255, null: false
    column :name, :string
    column :is_active, :boolean, default: true
    
    timestamps(type: :utc_datetime)
    
    index :users_email_index, [:email], unique: true
  end

  # Add this new table
  table :posts do
    column :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
    column :title, :string, null: false
    column :body, :text
    column :published_at, :utc_datetime
    column :user_id, :uuid, references: :users, on_delete: :delete_all
    
    timestamps(type: :utc_datetime)
    
    index :posts_user_id_index, [:user_id]
  end
end
```

Now apply the changes:

```bash
mix pg_pushex.push
```

You'll see:

```
Calculating diff...
Applying changes...
Executing: CREATE TABLE "posts" ("id" uuid PRIMARY KEY DEFAULT gen_random_uuid(), "title" varchar(255) NOT NULL, "body" text, "published_at" timestamp with time zone, "user_id" uuid, "inserted_at" timestamp with time zone NOT NULL, "updated_at" timestamp with time zone NOT NULL, FOREIGN KEY ("user_id") REFERENCES "users"(id) ON DELETE CASCADE)
Executing: CREATE INDEX "posts_user_id_index" ON "posts" ("user_id")
Push successful!
```

Notice how PgPushex:
1. **Only created the new table** — it didn't touch the existing `users` table
2. **Handled the foreign key** — automatically added the `references` constraint
3. **Ordered correctly** — created `users` reference before using it

## Step 8: Generate a Migration File (Optional)

If you prefer to generate traditional Ecto migration files:

```bash
mix pg_pushex.generate -r MyApp.Repo -s MyApp.Schema
```

This creates a file in `priv/repo/migrations/` that you can review and run with `mix ecto.migrate`.

## Next Steps

Now that you have PgPushex working, explore:

- **[Schema DSL Guide](./schema_dsl.md)** — Learn all available options
- **[Migrating from Ecto](./migrating_from_ecto.md)** — If you have existing migrations
- **[Advanced Patterns](./advanced_patterns.md)** — Complex schemas and best practices

## Common Issues

### "database does not exist"

Run `mix ecto.create` first.

### "permission denied"

Ensure your database user has CREATE privileges:

```sql
GRANT ALL PRIVILEGES ON DATABASE your_database TO your_user;
```

### "extension not found"

Some extensions need to be installed system-wide. For pgvector:

```bash
# On macOS with Homebrew
brew install pgvector

# On Ubuntu/Debian
sudo apt-get install postgresql-contrib
```

## Summary

You've learned how to:

- ✅ Add PgPushex to your project
- ✅ Define a schema with tables and columns
- ✅ Apply the schema to your database
- ✅ Evolve the schema by adding new tables
- ✅ Generate traditional migration files

Happy coding with PgPushex! 🚀
