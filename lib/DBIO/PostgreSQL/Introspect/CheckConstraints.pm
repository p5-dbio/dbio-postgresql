package DBIO::PostgreSQL::Introspect::CheckConstraints;
# ABSTRACT: Introspect PostgreSQL CHECK constraints
our $VERSION = '0.900000';

use strict;
use warnings;

=head1 DESCRIPTION

Fetches CHECK constraint metadata from C<pg_catalog.pg_constraint> where
C<contype = 'c'>.

=cut

=method fetch

    my $checks = DBIO::PostgreSQL::Introspect::CheckConstraints->fetch($dbh, $filter);

Returns a hashref keyed by C<schema.table>. Each value is a hashref keyed by
constraint name. Each entry has: C<constraint_name>, C<definition> (the CHECK
expression from C<pg_get_constraintdef>), C<columns> (ArrayRef of column names
the constraint references, may be empty for table-level checks).

=cut

sub fetch {
  my ($class, $dbh, $filter) = @_;

  my $sql = q{
    SELECT
      sn.nspname AS schema_name,
      cl.relname AS table_name,
      con.conname AS constraint_name,
      pg_catalog.pg_get_constraintdef(con.oid) AS definition,
      con.conkey AS column_numbers
    FROM pg_catalog.pg_constraint con
    JOIN pg_catalog.pg_class cl ON cl.oid = con.conrelid
    JOIN pg_catalog.pg_namespace sn ON sn.oid = cl.relnamespace
    WHERE con.contype = 'c'
      AND sn.nspname !~ '^pg_'
      AND sn.nspname != 'information_schema'
      AND NOT con.conislocal = false
  };

  my @bind;
  if ($filter && @$filter) {
    $sql .= ' AND sn.nspname = ANY($1)';
    push @bind, $filter;
  }

  $sql .= q{
    ORDER BY sn.nspname, cl.relname, con.conname
  };

  my $sth = $dbh->prepare($sql);
  $sth->execute(@bind);

  my %checks;
  while (my $row = $sth->fetchrow_hashref) {
    my $table_key = "$row->{schema_name}.$row->{table_name}";

    # Resolve column numbers to names
    my @col_names;
    if ($row->{column_numbers}) {
      my $nums = $row->{column_numbers};
      $nums =~ s/^\{|\}$//g;
      my @nums = grep { $_ > 0 } split /,/, $nums;

      if (@nums) {
        my $col_sth = $dbh->prepare(q{
          SELECT attname FROM pg_catalog.pg_attribute
          WHERE attrelid = (
            SELECT oid FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = $1 AND c.relname = $2
          )
          AND attnum = ANY($3)
          ORDER BY attnum
        });
        $col_sth->execute($row->{schema_name}, $row->{table_name}, \@nums);
        while (my ($name) = $col_sth->fetchrow_array) {
          push @col_names, $name;
        }
      }
    }

    $checks{$table_key}{ $row->{constraint_name} } = {
      constraint_name => $row->{constraint_name},
      definition      => $row->{definition},
      columns         => \@col_names,
    };
  }

  return \%checks;
}

1;
