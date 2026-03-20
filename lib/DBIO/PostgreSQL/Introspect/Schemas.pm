package DBIO::PostgreSQL::Introspect::Schemas;
# ABSTRACT: Introspect PostgreSQL schemas (namespaces)
our $VERSION = '0.900000';

use strict;
use warnings;

=head1 DESCRIPTION

Fetches PostgreSQL schema (namespace) metadata from C<pg_catalog.pg_namespace>.
System schemas (C<pg_*> and C<information_schema>) are excluded.

=cut

=method fetch

    my $schemas = DBIO::PostgreSQL::Introspect::Schemas->fetch($dbh, $filter);

Returns a hashref keyed by schema name. Each value is a hashref with keys
C<oid> and C<comment>. Pass an optional ArrayRef as C<$filter> to restrict
to specific schema names.

=cut

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
