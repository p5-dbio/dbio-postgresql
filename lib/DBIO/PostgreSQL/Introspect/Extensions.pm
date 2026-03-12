package DBIO::PostgreSQL::Introspect::Extensions;
# ABSTRACT: Introspect PostgreSQL extensions

use strict;
use warnings;

=head1 DESCRIPTION

Fetches installed PostgreSQL extension metadata from
C<pg_catalog.pg_extension>. The built-in C<plpgsql> extension is excluded
since it is always present.

=cut

=method fetch

    my $extensions = DBIO::PostgreSQL::Introspect::Extensions->fetch($dbh);

Returns a hashref keyed by extension name. Each entry has:
C<extension_name>, C<version>, C<schema_name> (the schema the extension's
objects live in), C<relocatable>.

No schema filter is accepted — extensions are database-level objects.

=cut

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
