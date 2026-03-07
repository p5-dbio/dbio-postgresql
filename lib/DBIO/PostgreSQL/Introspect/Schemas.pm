package DBIO::PostgreSQL::Introspect::Schemas;
# ABSTRACT: Introspect PostgreSQL schemas (namespaces)

use strict;
use warnings;

sub fetch {
  my ($class, $dbh, $filter) = @_;

  my $sql = q{
    SELECT
      n.nspname AS schema_name,
      n.oid AS schema_oid,
      pg_catalog.obj_description(n.oid, 'pg_namespace') AS comment
    FROM pg_catalog.pg_namespace n
    WHERE n.nspname !~ '^pg_'
      AND n.nspname != 'information_schema'
  };

  my @bind;
  if ($filter && @$filter) {
    $sql .= ' AND n.nspname = ANY($1)';
    push @bind, $filter;
  }

  $sql .= ' ORDER BY n.nspname';

  my $sth = $dbh->prepare($sql);
  $sth->execute(@bind);

  my %schemas;
  while (my $row = $sth->fetchrow_hashref) {
    $schemas{ $row->{schema_name} } = {
      oid     => $row->{schema_oid},
      comment => $row->{comment},
    };
  }

  return \%schemas;
}

1;
