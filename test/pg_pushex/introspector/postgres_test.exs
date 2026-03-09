defmodule PgPushex.Introspector.PostgresTest do
  use PgPushex.Integration.TestCase, async: false

  @moduletag :integration

  alias PgPushex.Introspector.Postgres

  describe "basic table introspection" do
    test "introspects empty database" do
      schema = introspect_schema()
      assert schema.tables == %{}
    end

    test "introspects single table with primary key" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY);")

      schema = introspect_schema()

      assert Map.has_key?(schema.tables, :users)
      users_table = schema.tables[:users]

      assert users_table.name == :users
      assert length(users_table.columns) == 1

      id_col = hd(users_table.columns)
      assert id_col.name == :id
      assert id_col.type == :serial
      assert id_col.primary_key == true
      assert id_col.null == false
    end

    test "introspects table with multiple columns" do
      execute_sql("""
        CREATE TABLE users (
          id serial PRIMARY KEY,
          name text NOT NULL,
          email text,
          age integer
        );
      """)

      schema = introspect_schema()

      users_table = schema.tables[:users]
      column_names = Enum.map(users_table.columns, & &1.name)

      assert :id in column_names
      assert :name in column_names
      assert :email in column_names
      assert :age in column_names
    end
  end

  describe "column types introspection" do
    test "introspects uuid type" do
      execute_sql("CREATE TABLE items (id uuid PRIMARY KEY);")

      schema = introspect_schema()
      id_col = hd(schema.table[:items].columns)

      assert id_col.type == :uuid
    end

    test "introspects string/text type" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, name text);")

      schema = introspect_schema()
      name_col = Enum.find(schema.tables[:items].columns, &(&1.name == :name))

      assert name_col.type == :string
    end

    test "introspects varchar with size" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, code varchar(50));")

      schema = introspect_schema()
      code_col = Enum.find(schema.tables[:items].columns, &(&1.name == :code))

      assert code_col.type == :string
      assert code_col.size == 50
    end

    test "introspects integer type" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, count integer);")

      schema = introspect_schema()
      count_col = Enum.find(schema.tables[:items].columns, &(&1.name == :count))

      assert count_col.type == :integer
    end

    test "introspects bigint type" do
      execute_sql("CREATE TABLE items (id bigserial PRIMARY KEY, value bigint);")

      schema = introspect_schema()
      value_col = Enum.find(schema.tables[:items].columns, &(&1.name == :value))

      assert value_col.type == :bigint
    end

    test "introspects smallint type" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, small smallint);")

      schema = introspect_schema()
      small_col = Enum.find(schema.tables[:items].columns, &(&1.name == :small))

      assert small_col.type == :smallint
    end

    test "introspects boolean type" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, active boolean);")

      schema = introspect_schema()
      active_col = Enum.find(schema.tables[:items].columns, &(&1.name == :active))

      assert active_col.type == :boolean
    end

    test "introspects float/double precision type" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, price double precision);")

      schema = introspect_schema()
      price_col = Enum.find(schema.tables[:items].columns, &(&1.name == :price))

      assert price_col.type == :float
    end

    test "introspects decimal/numeric type" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, amount numeric(10, 2));")

      schema = introspect_schema()
      amount_col = Enum.find(schema.tables[:items].columns, &(&1.name == :amount))

      assert amount_col.type == :decimal
    end

    test "introspects date type" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, created date);")

      schema = introspect_schema()
      created_col = Enum.find(schema.tables[:items].columns, &(&1.name == :created))

      assert created_col.type == :date
    end

    test "introspects time type" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, start_time time);")

      schema = introspect_schema()
      time_col = Enum.find(schema.tables[:items].columns, &(&1.name == :start_time))

      assert time_col.type == :time
    end

    test "introspects naive_datetime (timestamp without time zone)" do
      execute_sql(
        "CREATE TABLE items (id serial PRIMARY KEY, created_at timestamp without time zone);"
      )

      schema = introspect_schema()
      created_col = Enum.find(schema.tables[:items].columns, &(&1.name == :created_at))

      assert created_col.type == :naive_datetime
    end

    test "introspects utc_datetime (timestamp with time zone)" do
      execute_sql(
        "CREATE TABLE items (id serial PRIMARY KEY, created_at timestamp with time zone);"
      )

      schema = introspect_schema()
      created_col = Enum.find(schema.tables[:items].columns, &(&1.name == :created_at))

      assert created_col.type == :utc_datetime
    end

    test "introspects binary/bytea type" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, data bytea);")

      schema = introspect_schema()
      data_col = Enum.find(schema.tables[:items].columns, &(&1.name == :data))

      assert data_col.type == :binary
    end

    test "introspects jsonb/map type" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, meta jsonb);")

      schema = introspect_schema()
      meta_col = Enum.find(schema.tables[:items].columns, &(&1.name == :meta))

      assert meta_col.type == :map
    end
  end

  describe "serial and bigserial types" do
    test "introspects serial as serial type" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY);")

      schema = introspect_schema()
      id_col = hd(schema.tables[:items].columns)

      assert id_col.type == :serial
      assert id_col.primary_key == true
    end

    test "introspects bigserial as bigserial type" do
      execute_sql("CREATE TABLE items (id bigserial PRIMARY KEY);")

      schema = introspect_schema()
      id_col = hd(schema.tables[:items].columns)

      assert id_col.type == :bigserial
    end

    test "introspects identity column as serial" do
      execute_sql("CREATE TABLE items (id integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY);")

      schema = introspect_schema()
      id_col = hd(schema.tables[:items].columns)

      assert id_col.type == :serial
    end
  end

  describe "nullability introspection" do
    test "introspects NOT NULL column" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, name text NOT NULL);")

      schema = introspect_schema()
      name_col = Enum.find(schema.tables[:items].columns, &(&1.name == :name))

      assert name_col.null == false
    end

    test "introspects nullable column" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, name text);")

      schema = introspect_schema()
      name_col = Enum.find(schema.tables[:items].columns, &(&1.name == :name))

      assert name_col.null == true
    end

    test "primary key columns are always NOT NULL" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY);")

      schema = introspect_schema()
      id_col = hd(schema.tables[:items].columns)

      assert id_col.null == false
    end
  end

  describe "default values introspection" do
    test "introspects string default" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, status text DEFAULT 'active');")

      schema = introspect_schema()
      status_col = Enum.find(schema.tables[:items].columns, &(&1.name == :status))

      assert status_col.default == "active"
    end

    test "introspects integer default" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, count integer DEFAULT 0);")

      schema = introspect_schema()
      count_col = Enum.find(schema.tables[:items].columns, &(&1.name == :count))

      assert count_col.default == 0
    end

    test "introspects boolean default" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY, active boolean DEFAULT true);")

      schema = introspect_schema()
      active_col = Enum.find(schema.tables[:items].columns, &(&1.name == :active))

      assert active_col.default == true
    end

    test "introspects fragment default (function call)" do
      execute_sql("CREATE TABLE items (id uuid PRIMARY KEY DEFAULT gen_random_uuid());")

      schema = introspect_schema()
      id_col = hd(schema.tables[:items].columns)

      assert id_col.default == {:fragment, "gen_random_uuid()"}
    end

    test "introspects now() default" do
      execute_sql(
        "CREATE TABLE items (id serial PRIMARY KEY, created_at timestamp DEFAULT now());"
      )

      schema = introspect_schema()
      created_col = Enum.find(schema.tables[:items].columns, &(&1.name == :created_at))

      assert created_col.default == {:fragment, "now()"}
    end

    test "serial columns have no default in schema" do
      execute_sql("CREATE TABLE items (id serial PRIMARY KEY);")

      schema = introspect_schema()
      id_col = hd(schema.tables[:items].columns)

      assert id_col.default == nil
    end
  end

  describe "indexes introspection" do
    test "introspects simple index" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, email text);")
      execute_sql("CREATE INDEX users_email_index ON users (email);")

      schema = introspect_schema()

      users_table = schema.tables[:users]
      index = Enum.find(users_table.indexes, &(&1.name == :users_email_index))

      assert index != nil
      assert index.columns == [:email]
      assert index.unique == false
    end

    test "introspects unique index" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, email text);")
      execute_sql("CREATE UNIQUE INDEX users_email_unique ON users (email);")

      schema = introspect_schema()

      users_table = schema.tables[:users]
      index = Enum.find(users_table.indexes, &(&1.name == :users_email_unique))

      assert index != nil
      assert index.unique == true
    end

    test "introspects multi-column index" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY, first_name text, last_name text);")
      execute_sql("CREATE INDEX users_name_index ON users (first_name, last_name);")

      schema = introspect_schema()

      users_table = schema.tables[:users]
      index = Enum.find(users_table.indexes, &(&1.name == :users_name_index))

      assert index != nil
      assert index.columns == [:first_name, :last_name]
    end

    test "does not include primary key index" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY);")

      schema = introspect_schema()

      users_table = schema.tables[:users]
      assert users_table.indexes == []
    end
  end

  describe "foreign keys introspection" do
    test "introspects simple foreign key" do
      execute_sql("CREATE TABLE posts (id serial PRIMARY KEY);")

      execute_sql(
        "CREATE TABLE comments (id serial PRIMARY KEY, post_id integer REFERENCES posts(id));"
      )

      schema = introspect_schema()

      comments_table = schema.tables[:comments]
      post_id_col = Enum.find(comments_table.columns, &(&1.name == :post_id))

      assert post_id_col.references == :posts
    end

    test "introspects foreign key with ON DELETE CASCADE" do
      execute_sql("CREATE TABLE posts (id serial PRIMARY KEY);")

      execute_sql(
        "CREATE TABLE comments (id serial PRIMARY KEY, post_id integer REFERENCES posts(id) ON DELETE CASCADE);"
      )

      schema = introspect_schema()

      comments_table = schema.tables[:comments]
      fk = Enum.find(comments_table.foreign_keys, &(&1.column_name == :post_id))

      assert fk != nil
      assert fk.on_delete == :cascade
    end

    test "introspects foreign key with ON DELETE SET NULL" do
      execute_sql("CREATE TABLE posts (id serial PRIMARY KEY);")

      execute_sql(
        "CREATE TABLE comments (id serial PRIMARY KEY, post_id integer REFERENCES posts(id) ON DELETE SET NULL);"
      )

      schema = introspect_schema()

      comments_table = schema.tables[:comments]
      fk = Enum.find(comments_table.foreign_keys, &(&1.column_name == :post_id))

      assert fk.on_delete == :set_null
    end

    test "introspects foreign key with ON UPDATE CASCADE" do
      execute_sql("CREATE TABLE posts (id serial PRIMARY KEY);")

      execute_sql(
        "CREATE TABLE comments (id serial PRIMARY KEY, post_id integer REFERENCES posts(id) ON UPDATE CASCADE);"
      )

      schema = introspect_schema()

      comments_table = schema.tables[:comments]
      fk = Enum.find(comments_table.foreign_keys, &(&1.column_name == :post_id))

      assert fk.on_update == :cascade
    end
  end

  describe "multiple tables introspection" do
    test "introspects multiple tables" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY);")
      execute_sql("CREATE TABLE posts (id serial PRIMARY KEY);")
      execute_sql("CREATE TABLE comments (id serial PRIMARY KEY);")

      schema = introspect_schema()

      assert Map.has_key?(schema.tables, :users)
      assert Map.has_key?(schema.tables, :posts)
      assert Map.has_key?(schema.tables, :comments)
    end

    test "ignores schema_migrations table" do
      execute_sql("CREATE TABLE users (id serial PRIMARY KEY);")
      execute_sql("CREATE TABLE schema_migrations (version bigint);")

      schema = introspect_schema()

      assert Map.has_key?(schema.tables, :users)
      refute Map.has_key?(schema.tables, :schema_migrations)
    end
  end

  describe "composite primary key" do
    test "introspects composite primary key" do
      execute_sql(
        "CREATE TABLE user_roles (user_id integer, role_id integer, PRIMARY KEY (user_id, role_id));"
      )

      schema = introspect_schema()

      user_roles_table = schema.tables[:user_roles]
      pk_columns = Enum.filter(user_roles_table.columns, & &1.primary_key)

      assert length(pk_columns) == 2

      user_id_col = Enum.find(user_roles_table.columns, &(&1.name == :user_id))
      role_id_col = Enum.find(user_roles_table.columns, &(&1.name == :role_id))

      assert user_id_col.primary_key == true
      assert role_id_col.primary_key == true
    end
  end
end
