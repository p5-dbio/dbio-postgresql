# DBIO-PostgreSQL

PostgreSQL driver distribution for DBIO.

## Scope

- Provides PostgreSQL storage behavior: `DBIO::PostgreSQL::Storage`
- Provides PostgreSQL SQL/deploy/introspection/diff modules
- Owns PostgreSQL-specific tests from the historical DBIx::Class monolithic test layout

## Migration Notes

- Legacy class name: `DBIx::Class::Storage::DBI::Pg`
- New class in this distro: `DBIO::PostgreSQL::Storage`

When installed, DBIO core can autodetect PostgreSQL DSNs and load the storage
class through `DBIO::Storage::DBI` driver registration.

## Testing

Set environment variables for integration tests:

- `DBIOTEST_PG_DSN`
- `DBIOTEST_PG_USER`
- `DBIOTEST_PG_PASS`

`t/20-sqlmaker-pg.t` can run without a live database by using
`DBIO::Test` hybrid fake storage with
`storage_type => 'DBIO::PostgreSQL::Storage'`.
