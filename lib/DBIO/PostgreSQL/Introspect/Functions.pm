package DBIO::PostgreSQL::Introspect::Functions;
# ABSTRACT: Introspect PostgreSQL functions

use strict;
use warnings;

sub fetch {
  my ($class, $dbh, $filter) = @_;

  my $sql = q{
    SELECT
      n.nspname AS schema_name,
      p.proname AS function_name,
      p.oid AS function_oid,
      pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_args,
      pg_catalog.pg_get_functiondef(p.oid) AS definition,
      l.lanname AS language,
      p.provolatile AS volatility,
      p.proisstrict AS is_strict,
      p.prosecdef AS security_definer,
      pg_catalog.format_type(p.prorettype, NULL) AS return_type
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_catalog.pg_language l ON l.oid = p.prolang
    WHERE n.nspname !~ '^pg_'
      AND n.nspname != 'information_schema'
      AND p.prokind IN ('f', 'p')
  };

  my @bind;
  if ($filter && @$filter) {
    $sql .= ' AND n.nspname = ANY($1)';
    push @bind, $filter;
  }

  $sql .= ' ORDER BY n.nspname, p.proname';

  my $sth = $dbh->prepare($sql);
  $sth->execute(@bind);

  my %functions;
  while (my $row = $sth->fetchrow_hashref) {
    my $key = "$row->{schema_name}.$row->{function_name}($row->{identity_args})";
    $functions{$key} = {
      schema_name      => $row->{schema_name},
      function_name    => $row->{function_name},
      identity_args    => $row->{identity_args},
      definition       => $row->{definition},
      language         => $row->{language},
      volatility       => $row->{volatility},
      is_strict        => $row->{is_strict} ? 1 : 0,
      security_definer => $row->{security_definer} ? 1 : 0,
      return_type      => $row->{return_type},
    };
  }

  return \%functions;
}

1;
