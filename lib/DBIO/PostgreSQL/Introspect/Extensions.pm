package DBIO::PostgreSQL::Introspect::Extensions;
# ABSTRACT: Introspect PostgreSQL extensions

use strict;
use warnings;

sub fetch {
  my ($class, $dbh) = @_;

  my $sql = q{
    SELECT
      e.extname AS extension_name,
      e.extversion AS version,
      n.nspname AS schema_name,
      e.extrelocatable AS relocatable
    FROM pg_catalog.pg_extension e
    JOIN pg_catalog.pg_namespace n ON n.oid = e.extnamespace
    WHERE e.extname != 'plpgsql'
    ORDER BY e.extname
  };

  my $sth = $dbh->prepare($sql);
  $sth->execute;

  my %extensions;
  while (my $row = $sth->fetchrow_hashref) {
    $extensions{ $row->{extension_name} } = {
      extension_name => $row->{extension_name},
      version        => $row->{version},
      schema_name    => $row->{schema_name},
      relocatable    => $row->{relocatable} ? 1 : 0,
    };
  }

  return \%extensions;
}

1;
