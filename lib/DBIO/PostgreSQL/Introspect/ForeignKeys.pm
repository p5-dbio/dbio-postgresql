package DBIO::PostgreSQL::Introspect::ForeignKeys;
# ABSTRACT: Introspect PostgreSQL foreign keys
our $VERSION = '0.900000';

use strict;
use warnings;

=head1 DESCRIPTION

Fetches PostgreSQL foreign key metadata from C<pg_catalog.pg_constraint>,
including ordered local and remote columns plus referential actions and
deferrability.

=cut

=method fetch

    my $foreign_keys = DBIO::PostgreSQL::Introspect::ForeignKeys->fetch($dbh, $filter);

Returns a hashref keyed by C<schema.table>. Each value is an ArrayRef of
foreign key hashrefs with keys: C<constraint_name>, C<remote_schema>,
C<remote_table>, C<local_columns>, C<remote_columns>, C<on_delete>,
C<on_update>, and C<is_deferrable>.

=cut

sub fetch {
  my ($class, $dbh, $filter) = @_;

  my %pg_rules = (
    a => 'NO ACTION',
    r => 'RESTRICT',
    c => 'CASCADE',
    n => 'SET NULL',
    d => 'SET DEFAULT',
  );

  my $sql = q{
    SELECT
      from_ns.nspname AS local_schema,
      from_class.relname AS local_table,
      constr.conname AS constraint_name,
      to_ns.nspname AS remote_schema,
      to_class.relname AS remote_table,
      ord.n AS key_seq,
      from_col.attname AS local_column,
      to_col.attname AS remote_column,
      constr.confdeltype AS on_delete,
      constr.confupdtype AS on_update,
      constr.condeferrable AS is_deferrable
    FROM pg_catalog.pg_constraint constr
    JOIN pg_catalog.pg_class from_class ON from_class.oid = constr.conrelid
    JOIN pg_catalog.pg_namespace from_ns ON from_ns.oid = from_class.relnamespace
    JOIN pg_catalog.pg_class to_class ON to_class.oid = constr.confrelid
    JOIN pg_catalog.pg_namespace to_ns ON to_ns.oid = to_class.relnamespace
    JOIN pg_catalog.generate_subscripts(constr.conkey, 1) AS ord(n) ON true
    JOIN pg_catalog.pg_attribute from_col
      ON from_col.attrelid = constr.conrelid
     AND from_col.attnum = constr.conkey[ord.n]
    JOIN pg_catalog.pg_attribute to_col
      ON to_col.attrelid = constr.confrelid
     AND to_col.attnum = constr.confkey[ord.n]
    WHERE constr.contype = 'f'
      AND from_ns.nspname !~ '^pg_'
      AND from_ns.nspname != 'information_schema'
  };

  my @bind;
  if ($filter && @$filter) {
    $sql .= ' AND from_ns.nspname = ANY($1)';
    push @bind, $filter;
  }

  $sql .= q{
    ORDER BY from_ns.nspname, from_class.relname, constr.conname, ord.n
  };

  my $sth = $dbh->prepare($sql);
  $sth->execute(@bind);

  my %foreign_keys;
  while (my $row = $sth->fetchrow_hashref) {
    my $table_key = "$row->{local_schema}.$row->{local_table}";
    my $constraint = ($foreign_keys{$table_key} ||= {})->{ $row->{constraint_name} } ||= {
      constraint_name => $row->{constraint_name},
      remote_schema   => $row->{remote_schema},
      remote_table    => $row->{remote_table},
      local_columns   => [],
      remote_columns  => [],
      on_delete       => $pg_rules{ $row->{on_delete} },
      on_update       => $pg_rules{ $row->{on_update} },
      is_deferrable   => $row->{is_deferrable} ? 1 : 0,
    };

    push @{ $constraint->{local_columns} },  $row->{local_column};
    push @{ $constraint->{remote_columns} }, $row->{remote_column};
  }

  return {
    map {
      my $key = $_;
      $key => [
        map { $foreign_keys{$key}{$_} }
        sort keys %{ $foreign_keys{$key} }
      ]
    } sort keys %foreign_keys
  };
}

1;
