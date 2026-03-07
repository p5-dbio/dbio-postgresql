use strict;
use warnings;
use Test::More;

use DBIO::PostgreSQL::Diff::Column;

my $tables = {
  'public.users' => { schema_name => 'public', table_name => 'users' },
};

# Add column
my @ops = DBIO::PostgreSQL::Diff::Column->diff(
  { 'public.users' => [
    { column_name => 'id', data_type => 'integer', not_null => 1 },
  ]},
  { 'public.users' => [
    { column_name => 'id', data_type => 'integer', not_null => 1 },
    { column_name => 'email', data_type => 'text', not_null => 0 },
  ]},
  $tables, $tables,
);

is(scalar @ops, 1, 'one column to add');
is($ops[0]->action, 'add', 'action is add');
is($ops[0]->column_name, 'email', 'column name');
like($ops[0]->as_sql, qr/ALTER TABLE public\.users ADD COLUMN email text/, 'add column DDL');

# Drop column
@ops = DBIO::PostgreSQL::Diff::Column->diff(
  { 'public.users' => [
    { column_name => 'id', data_type => 'integer', not_null => 1 },
    { column_name => 'old_col', data_type => 'text', not_null => 0 },
  ]},
  { 'public.users' => [
    { column_name => 'id', data_type => 'integer', not_null => 1 },
  ]},
  $tables, $tables,
);

is(scalar @ops, 1, 'one column to drop');
is($ops[0]->action, 'drop', 'action is drop');
like($ops[0]->as_sql, qr/DROP COLUMN old_col/, 'drop column DDL');

# Alter column type
@ops = DBIO::PostgreSQL::Diff::Column->diff(
  { 'public.users' => [
    { column_name => 'name', data_type => 'varchar(50)', not_null => 0 },
  ]},
  { 'public.users' => [
    { column_name => 'name', data_type => 'text', not_null => 0 },
  ]},
  $tables, $tables,
);

is(scalar @ops, 1, 'one column altered');
is($ops[0]->action, 'alter', 'action is alter');
like($ops[0]->as_sql, qr/ALTER COLUMN name TYPE text/, 'alter column DDL');

done_testing;
