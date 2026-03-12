# CLAUDE.md — DBIO::PostgreSQL

## Project Vision

PostgreSQL-specific schema management for DBIO (the DBIx::Class fork, see ../dbio/). Instead of the
database-agnostic approach of SQL::Translator (which loses PostgreSQL features), this module
embraces PostgreSQL fully — using its own catalog for introspection, its own DDL for deployment,
and a test-deploy-and-compare strategy for diffs.

**Status**: Active development.

## Namespace

- `DBIO::PostgreSQL` — main distribution
- NOT `DBIx::Class::PostgreSQL` — this is for the DBIO fork (see ../dbio/) specifically

## Core Concept: Three-Layer PostgreSQL Hierarchy

PostgreSQL has a real hierarchy that DBIO currently flattens:

```
PostgreSQL Cluster
  └── Database
       └── Schema (Namespace: public, auth, api, ...)
            ├── Table
            ├── View
            ├── Type (Enum, Composite, Range)
            ├── Function / Trigger
            ├── Sequence
            └── Index
       └── Extension (database-level, but schema-aware)
```

This module maps that hierarchy into DBIO with three component layers:

### Layer 1: Database (DBIO::Schema component)

```perl
package MyApp::DB;
use base 'DBIO::Schema';
__PACKAGE__->load_components('PostgreSQL');

__PACKAGE__->pg_schemas(qw( public auth api ));
__PACKAGE__->pg_extensions(qw( pgcrypto uuid-ossp postgis ));
__PACKAGE__->pg_search_path(qw( public ));
__PACKAGE__->pg_settings({
    'default_text_search_config' => 'pg_catalog.german',
});
```

### Layer 2: PgSchema (new intermediate layer)

Models PostgreSQL schemas (namespaces) as first-class objects:

```perl
package MyApp::DB::PgSchema::Auth;
use base 'DBIO::PostgreSQL::PgSchema';

__PACKAGE__->pg_schema_name('auth');

# Enums belong to a pg schema
__PACKAGE__->pg_enum('role_type'   => [qw( admin moderator user guest )]);
__PACKAGE__->pg_enum('status_type' => [qw( active inactive suspended )]);

# Composite types
__PACKAGE__->pg_type('address_type' => {
    street  => 'text',
    city    => 'text',
    zip     => 'varchar(10)',
    country => 'varchar(2)',
});

# Functions
__PACKAGE__->pg_function('update_modified_at' => q{
    CREATE OR REPLACE FUNCTION auth.update_modified_at()
    RETURNS TRIGGER AS $$
    BEGIN
        NEW.modified_at = NOW();
        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
});
```

### Layer 3: Result (Result component)

```perl
package MyApp::DB::Result::User;
use base 'DBIO::Core';
__PACKAGE__->load_components('PostgreSQL::Result');

__PACKAGE__->pg_schema('auth');       # belongs to auth namespace
__PACKAGE__->table('users');          # → auth.users

__PACKAGE__->add_columns(
    id => {
        data_type     => 'uuid',
        default_value => \'gen_random_uuid()',
    },
    role => {
        data_type    => 'enum',
        pg_enum_type => 'role_type',
    },
    tags => {
        data_type => 'text[]',
    },
    metadata => {
        data_type     => 'jsonb',
        default_value => '{}',
    },
    address => {
        data_type    => 'composite',
        pg_type_name => 'address_type',
    },
    embedding => {
        data_type => 'vector(1536)',    # pgvector
    },
);

# PostgreSQL-specific indexes
__PACKAGE__->pg_index('idx_users_tags' => {
    using   => 'gin',
    columns => ['tags'],
});

__PACKAGE__->pg_index('idx_users_active' => {
    columns => ['role'],
    where   => "role != 'suspended'",   # partial index
});

__PACKAGE__->pg_index('idx_users_name_lower' => {
    expression => 'lower(name)',        # expression index
});

__PACKAGE__->pg_index('idx_users_embedding' => {
    using   => 'ivfflat',              # pgvector
    columns => ['embedding'],
    with    => { lists => 100 },
});

# Triggers
__PACKAGE__->pg_trigger('users_modified_at' => {
    when    => 'BEFORE',
    event   => 'UPDATE',
    execute => 'auth.update_modified_at()',
});

# Row Level Security
__PACKAGE__->pg_rls({
    enable   => 1,
    force    => 1,
    policies => {
        users_own_data => {
            for   => 'ALL',
            using => 'id = current_setting($$app.current_user_id$$)::uuid',
        },
    },
});
```

## Architecture

### Module Structure

```
lib/DBIO/
├── PostgreSQL.pm                        # Schema component (Database layer)
├── PostgreSQL/
│   ├── Storage.pm                       # PostgreSQL storage (replaces Storage::DBI::Pg)
│   ├── PgSchema.pm                      # Base class for PG schema namespaces
│   ├── Result.pm                        # Result component
│   │
│   ├── Introspect.pm                    # pg_catalog → internal model
│   ├── Introspect/
│   │   ├── Schemas.pm
│   │   ├── Tables.pm
│   │   ├── Columns.pm
│   │   ├── Types.pm                     # Enums, Composites, Ranges
│   │   ├── Indexes.pm
│   │   ├── Triggers.pm
│   │   ├── Functions.pm
│   │   ├── Extensions.pm
│   │   ├── Policies.pm                  # Row Level Security
│   │   └── Sequences.pm
│   │
│   ├── Diff.pm                          # Compare two introspected models
│   ├── Diff/
│   │   ├── Schema.pm
│   │   ├── Table.pm
│   │   ├── Column.pm
│   │   ├── Type.pm
│   │   ├── Index.pm
│   │   ├── Function.pm
│   │   ├── Trigger.pm
│   │   ├── Policy.pm
│   │   └── Extension.pm
│   │
│   ├── DDL.pm                           # Diff → PostgreSQL DDL statements
│   └── Deploy.pm                        # Orchestration: install, diff, upgrade
```

### Deploy Flow (Test Deploy + Compare)

The key innovation: instead of trying to generate diffs from abstract representations,
we deploy to a temporary database and let PostgreSQL compare with itself.

```perl
my $deploy = DBIO::PostgreSQL::Deploy->new(
    schema => MyApp::DB->connect($dsn),
);

# --- Fresh install ---
$deploy->install;

# --- Upgrade via test-deploy ---
my $diff = $deploy->diff;
#   1. CREATE DATABASE temp_xxxx
#   2. Deploy desired schema from DBIO classes there
#   3. Introspect both DBs via pg_catalog
#   4. Compare the two models
#   5. DROP DATABASE temp_xxxx

say $diff->as_sql;
say $diff->summary;

$deploy->apply($diff);

# --- Or one-step ---
$deploy->upgrade;
```

### Introspection Strategy

All introspection goes through `pg_catalog` and `information_schema`:

- `pg_catalog.pg_namespace` → schemas
- `pg_catalog.pg_class` + `pg_attribute` → tables, columns
- `pg_catalog.pg_type` + `pg_enum` → types, enum values
- `pg_catalog.pg_index` + `pg_am` → indexes (incl. type: btree/gin/gist/brin/ivfflat)
- `pg_catalog.pg_trigger` → triggers
- `pg_catalog.pg_proc` → functions
- `pg_catalog.pg_extension` → extensions
- `pg_catalog.pg_policy` → RLS policies
- `pg_catalog.pg_constraint` → constraints (FK, UNIQUE, CHECK, EXCLUDE)
- `pg_get_indexdef()`, `pg_get_constraintdef()`, `pg_get_triggerdef()` → exact DDL

### Diff Output

```perl
$diff->as_sql;
# ALTER TYPE auth.role_type ADD VALUE 'superadmin';
# ALTER TABLE auth.users ADD COLUMN avatar text;
# CREATE INDEX CONCURRENTLY idx_users_avatar ON auth.users (avatar);
# DROP INDEX idx_users_old;

$diff->summary;
# Schema auth:
#   Type role_type: +1 value (superadmin)
#   Table users:
#     +column: avatar (text)
#     +index: idx_users_avatar
#     -index: idx_users_old

$diff->operations;
# Returns structured list of DBIO::PostgreSQL::Diff::* objects
```

## PostgreSQL Features Covered

### Fully Supported (Priority 1)
- Schemas (namespaces): CREATE/DROP/ALTER SCHEMA
- Tables: CREATE/ALTER/DROP with all column types
- Enums: CREATE TYPE, ALTER TYPE ADD VALUE (order-aware)
- Indexes: btree, gin, gist, brin, hash — partial, expression, INCLUDE
- Constraints: PRIMARY KEY, UNIQUE, CHECK, EXCLUDE, FOREIGN KEY
- Sequences: owned by columns, GENERATED ALWAYS/BY DEFAULT AS IDENTITY
- Extensions: CREATE/DROP EXTENSION

### Fully Supported (Priority 2)
- Composite Types: CREATE TYPE ... AS (...)
- Functions: CREATE/REPLACE FUNCTION (for triggers etc.)
- Triggers: BEFORE/AFTER/INSTEAD OF, per-row/per-statement
- Views: CREATE/REPLACE VIEW, materialized views
- Row Level Security: policies, ENABLE/FORCE

### Fully Supported (Priority 3)
- Partitioned Tables: RANGE, LIST, HASH
- Tablespaces
- Range Types
- Domain Types
- Foreign Tables (FDW)
- Generated Columns (STORED)
- Statistics objects (CREATE STATISTICS)

## Use Cases This Enables

### Multi-Tenant via PG Schemas
```perl
# Each tenant gets their own PostgreSQL schema
foreach my $tenant (@tenants) {
    $deploy->install_schema($tenant->schema_name);
}
# search_path per connection for tenant isolation
```

### API Schema Separation
```perl
__PACKAGE__->pg_schemas(qw( internal api ));
# internal.users → full table
# api.users_view → restricted view for API layer
```

### Extension-Heavy Stacks
```perl
__PACKAGE__->pg_extensions(qw(
    pgcrypto        # gen_random_uuid()
    postgis          # geography, geometry
    pg_trgm          # trigram similarity search
    pgvector         # AI embeddings
    timescaledb      # time-series
));
```

## Dependencies

- DBIO (from ../dbio/)
- Moo or Moose (whatever DBIO uses)
- DBI + DBD::Pg
- PostgreSQL 14+ (for full feature coverage)

## Testing Strategy

- **Unit tests** (no DB): annotation parsing, DDL generation, diff logic
- **Integration tests** (need PostgreSQL): introspection, deploy, roundtrip
- PostgreSQL test instance via: existing local server, Docker, or `pg_tmp`
- Environment variable: `TEST_DBIO_POSTGRESQL_DSN` for integration tests
- Each test gets its own temporary database (CREATE/DROP DATABASE)

## Important Design Decisions

### Why not SQL::Translator?
- SQL::Translator is database-agnostic → loses PostgreSQL-specific features
- Its diff algorithm produces suboptimal/incorrect migrations for PostgreSQL
- Enum support is broken, partial indexes not supported, JSONB treated as text
- We don't need abstraction — we're PostgreSQL-specific by design

### Why test-deploy instead of class-to-DDL diff?
- PostgreSQL comparing with itself is always correct
- No need to maintain a DDL generator that might drift from reality
- Catches edge cases automatically (column ordering, implicit defaults, etc.)
- The temp DB deploy is fast (schema-only, no data)

### Why a separate PgSchema layer?
- PostgreSQL schemas are fundamental to its architecture
- Enums, types, functions all belong to a schema — not to a table
- Multi-tenant patterns depend on schema isolation
- Without it, everything gets dumped into "public" and we lose structure

### Column type handling
- Don't try to map PostgreSQL types to abstract types and back
- Store the exact PostgreSQL type as declared
- Introspect the exact PostgreSQL type from pg_catalog
- Compare types as PostgreSQL strings — no lossy translation layer

## Build System

Uses Dist::Zilla with `[@DBIO]` plugin bundle. PodWeaver with `=attr` and `=method` collectors.

## Relationship to DBIO

This module is designed for DBIO (the DBIx::Class fork). It depends on DBIO's
component system (load_components) and Result class architecture. The namespace
is `DBIO::PostgreSQL`, not `DBIx::Class::PostgreSQL`.

When DBIO is released, the API might need adjustment depending on:
- Whether DBIO changes the component loading mechanism
- Whether DBIO::Core differs from DBIx::Class::Core
- How DBIO handles `table()` and schema qualification

These adjustments should be minor since the component architecture is stable.
