package DBIO::PostgreSQL::Introspect::Indexes;
# ABSTRACT: Introspect PostgreSQL indexes
our $VERSION = '0.900000';

use strict;
use warnings;

=head1 DESCRIPTION

Fetches index metadata from C<pg_catalog.pg_index>, including access method,
uniqueness, primary key flag, validity, the full index definition string from
C<pg_get_indexdef>, partial index predicates, and expression index expressions.

=cut

=method fetch

    my $indexes = DBIO::PostgreSQL::Introspect::Indexes->fetch($dbh, $filter);

Returns a hashref keyed by C<schema.table>. Each value is a hashref keyed by
index name. Each index entry has: C<index_name>, C<access_method>, C<is_unique>,
C<is_primary>, C<is_valid>, C<definition> (full C<pg_get_indexdef> output),
C<predicate>, C<expressions>, C<columns> (ArrayRef of column names, empty for
expression-only indexes).

=cut

sub fetch {
  my ($class, $dbh, $filter) = @_;

  my $sql = q{
    SELECT
      sn.nspname AS schema_name,
      ct.relname AS table_name,
      ci.relname AS index_name,
      am.amname AS access_method,
      i.indisunique AS is_unique,
      i.indisprimary AS is_primary,
      i.indisvalid AS is_valid,
      pg_catalog.pg_get_indexdef(i.indexrelid) AS definition,
      pg_catalog.pg_get_expr(i.indpred, i.indrelid) AS predicate,
      pg_catalog.pg_get_expr(i.indexprs, i.indrelid) AS expressions,
      array_agg(a.attname ORDER BY k.n) AS column_names,
      ci.reloptions AS storage_params
    FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class ci ON ci.oid = i.indexrelid
    JOIN pg_catalog.pg_class ct ON ct.oid = i.indrelid
    JOIN pg_catalog.pg_namespace sn ON sn.oid = ct.relnamespace
    JOIN pg_catalog.pg_am am ON am.oid = ci.relam
    LEFT JOIN LATERAL unnest(i.indkey) WITH ORDINALITY AS k(attnum, n) ON true
    LEFT JOIN pg_catalog.pg_attribute a
      ON a.attrelid = i.indrelid AND a.attnum = k.attnum
    WHERE sn.nspname !~ '^pg_'
      AND sn.nspname != 'information_schema'
      AND ct.relkind IN ('r', 'm', 'p')
  };

  my @bind;
  if ($filter && @$filter) {
    $sql .= ' AND sn.nspname = ANY($1)';
    push @bind, $filter;
  }

  $sql .= q{
    GROUP BY sn.nspname, ct.relname, ci.relname, am.amname,
             i.indisunique, i.indisprimary, i.indisvalid,
             i.indexrelid, i.indrelid, i.indpred, i.indexprs,
             ci.reloptions
    ORDER BY sn.nspname, ct.relname, ci.relname
  };

  my $sth = $dbh->prepare($sql);
  $sth->execute(@bind);

  my %indexes;
  while (my $row = $sth->fetchrow_hashref) {
    my $table_key = "$row->{schema_name}.$row->{table_name}";
    my $columns = $row->{column_names};
    if (!ref $columns) {
      $columns =~ s/^\{|\}$//g;
      $columns = [ grep { $_ ne 'NULL' } split /,/, $columns ];
    }
    $indexes{$table_key}{ $row->{index_name} } = {
      index_name    => $row->{index_name},
      access_method => $row->{access_method},
      is_unique     => $row->{is_unique} ? 1 : 0,
      is_primary    => $row->{is_primary} ? 1 : 0,
      is_valid      => $row->{is_valid} ? 1 : 0,
      definition    => $row->{definition},
      predicate     => $row->{predicate},
      expressions   => $row->{expressions},
      columns         => $columns,
      include_columns => $class->_parse_include($row->{definition}),
      storage_params  => $class->_parse_storage_params($row->{storage_params}),
    };
  }

  return \%indexes;
}

sub _parse_include {
  my ($class, $definition) = @_;
  return [] unless $definition;
  if ($definition =~ /\bINCLUDE\s*\(([^)]+)\)/i) {
    my $cols = $1;
    return [ map { s/^\s+|\s+$//g; s/^"|"$//g; $_ } split /,/, $cols ];
  }
  return [];
}

sub _parse_storage_params {
  my ($class, $reloptions) = @_;
  return {} unless $reloptions;
  my $raw = $reloptions;
  $raw =~ s/^\{|\}$//g if !ref $raw;
  my @items = ref $raw ? @$raw : split /,/, $raw;
  my %params;
  for my $item (@items) {
    $item =~ s/^\s+|\s+$//g;
    if ($item =~ /^(.+?)=(.+)$/) {
      $params{$1} = $2;
    }
  }
  return \%params;
}

1;
