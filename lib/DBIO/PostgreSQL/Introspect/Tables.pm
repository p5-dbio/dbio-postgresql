package DBIO::PostgreSQL::Introspect::Tables;
# ABSTRACT: Introspect PostgreSQL tables

use strict;
use warnings;

=head1 DESCRIPTION

Fetches PostgreSQL table (and view, materialized view, foreign table, and
partitioned table) metadata from C<pg_catalog.pg_class>.

=cut

=method fetch

    my $tables = DBIO::PostgreSQL::Introspect::Tables->fetch($dbh, $filter);

Returns a hashref keyed by C<schema.table>. Each value is a hashref with
keys: C<schema_name>, C<table_name>, C<oid>, C<kind> (pg relkind char),
C<kind_label> (human-readable), C<persistence>, C<comment>, C<rls_enabled>,
C<rls_forced>.

=cut

sub fetch {
  my ($class, $dbh, $filter) = @_;

  my $sql = q{
    SELECT
      n.nspname AS schema_name,
      c.relname AS table_name,
      c.oid AS table_oid,
      c.relkind AS kind,
      c.relpersistence AS persistence,
      CASE c.relkind
        WHEN 'r' THEN 'table'
        WHEN 'v' THEN 'view'
        WHEN 'm' THEN 'materialized_view'
        WHEN 'f' THEN 'foreign_table'
        WHEN 'p' THEN 'partitioned_table'
      END AS kind_label,
      pg_catalog.obj_description(c.oid, 'pg_class') AS comment,
      c.relrowsecurity AS rls_enabled,
      c.relforcerowsecurity AS rls_forced
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind IN ('r', 'v', 'm', 'f', 'p')
      AND n.nspname !~ '^pg_'
      AND n.nspname != 'information_schema'
  };

  my @bind;
  if ($filter && @$filter) {
    $sql .= ' AND n.nspname = ANY($1)';
    push @bind, $filter;
  }

  $sql .= ' ORDER BY n.nspname, c.relname';

  my $sth = $dbh->prepare($sql);
  $sth->execute(@bind);

  my %tables;
  while (my $row = $sth->fetchrow_hashref) {
    my $key = "$row->{schema_name}.$row->{table_name}";
    $tables{$key} = {
      schema_name => $row->{schema_name},
      table_name  => $row->{table_name},
      oid         => $row->{table_oid},
      kind        => $row->{kind},
      kind_label  => $row->{kind_label},
      persistence => $row->{persistence},
      comment     => $row->{comment},
      rls_enabled => $row->{rls_enabled} ? 1 : 0,
      rls_forced  => $row->{rls_forced} ? 1 : 0,
    };
  }

  return \%tables;
}

1;
