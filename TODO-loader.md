# DBIO::PostgreSQL::Loader TODO

Ported from DBIx::Class::Schema::Loader::DBI::Pg. Lives at `DBIO::PostgreSQL::Loader`.

## Integration

- [x] Merge with existing dbio-postgresql pg_catalog introspection (avoid duplication)
- [x] Loader now reuses `DBIO::PostgreSQL::Introspect` through `DBIO::PostgreSQL::Loader::Model`
- [ ] Run the new live loader test with a real PostgreSQL database (`t/24-loader-live.t`, needs `DBIOTEST_PG_DSN`)

## PostgreSQL-Specific Improvements

- [x] Introspect pgvector columns → loader metadata normalizes `vector(dims)` to `data_type => 'vector', size => dims`
- [x] Introspect enum types → loader metadata now uses the shared type model and captures enum value lists
- [x] Introspect range types → loader metadata retains range types such as `int4range`
- [x] Introspect jsonb columns with proper type annotation
- [x] Support schema-qualified table names in multi-schema setups
- [ ] Introspect CHECK constraints as column metadata
- [x] Introspect partial indexes and expression indexes
- [x] Support RLS policy awareness via `pg_rls` loader metadata
- [x] Introspect generated/computed columns (PostgreSQL 12+)
- [x] Introspect identity columns (GENERATED ALWAYS/BY DEFAULT)
- [ ] Generate `DBIO::PostgreSQL::PgSchema` classes or equivalent schema-level metadata for user-defined types/functions/extensions
- [ ] Capture index storage parameters / INCLUDE columns from introspection for fuller round-tripping

## Testing

- [x] Add offline loader-model coverage for enum, jsonb, vector, range, partial/expression indexes, triggers, and RLS
- [x] Add offline DDL coverage for PostgreSQL result metadata (`pg_index`, `pg_trigger`, `pg_rls`)
- [x] Add an optional real PostgreSQL loader test (`t/24-loader-live.t`)
- [ ] Run the live loader test against a real PostgreSQL database
- [ ] Expand live coverage for arrays, hstore, and extension-backed types such as pgvector
- [ ] Add output-level checks for Cake/Candy generation if loader output modes are extended in that direction
