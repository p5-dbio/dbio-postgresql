package DBIO::PostgreSQL::Introspect::Types;
# ABSTRACT: Introspect PostgreSQL types (enums, composites, ranges)
our $VERSION = '0.900000';

use strict;
use warnings;

=head1 DESCRIPTION

Fetches user-defined type metadata from C<pg_catalog>: enum types (with
ordered values), composite types (with attributes), and range types (with
subtype). System types are excluded.

=cut

=method fetch

    my $types = DBIO::PostgreSQL::Introspect::Types->fetch($dbh, $filter);

Returns a hashref keyed by C<schema.type_name>. Each value is a hashref with
C<schema_name>, C<type_name>, C<type_kind> (C<enum>, C<composite>, or
C<range>), and kind-specific fields:

=over 4

=item enum: C<values> (ArrayRef, sorted by C<enumsortorder>)

=item composite: C<attributes> (ArrayRef of C<{ name, type, ordinal }>)

=item range: C<subtype> (subtype name string)

=back

=cut

sub fetch {
  my ($class, $dbh, $filter) = @_;

  my $types = {};

  $class->_fetch_enums($dbh, $filter, $types);
  $class->_fetch_composites($dbh, $filter, $types);
  $class->_fetch_ranges($dbh, $filter, $types);

  return $types;
}

sub _fetch_enums {
  my ($class, $dbh, $filter, $types) = @_;

  my $sql = q{
    SELECT
      n.nspname AS schema_name,
      t.typname AS type_name,
      array_agg(e.enumlabel ORDER BY e.enumsortorder) AS enum_values
    FROM pg_catalog.pg_type t
    JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
    JOIN pg_catalog.pg_enum e ON e.enumtypid = t.oid
    WHERE t.typtype = 'e'
      AND n.nspname !~ '^pg_'
      AND n.nspname != 'information_schema'
  };

  my @bind;
  if ($filter && @$filter) {
    $sql .= ' AND n.nspname = ANY($1)';
    push @bind, $filter;
  }

  $sql .= ' GROUP BY n.nspname, t.typname ORDER BY n.nspname, t.typname';

  my $sth = $dbh->prepare($sql);
  $sth->execute(@bind);

  while (my $row = $sth->fetchrow_hashref) {
    my $key = "$row->{schema_name}.$row->{type_name}";
    # DBD::Pg returns array_agg as a string like {val1,val2}
    my $values = $row->{enum_values};
    if (!ref $values) {
      $values =~ s/^\{|\}$//g;
      $values = [ split /,/, $values ];
    }
    $types->{$key} = {
      schema_name => $row->{schema_name},
      type_name   => $row->{type_name},
      type_kind   => 'enum',
      values      => $values,
    };
  }
}

sub _fetch_composites {
  my ($class, $dbh, $filter, $types) = @_;

  my $sql = q{
    SELECT
      n.nspname AS schema_name,
      t.typname AS type_name,
      a.attname AS attr_name,
      a.attnum AS ordinal,
      pg_catalog.format_type(a.atttypid, a.atttypmod) AS attr_type
    FROM pg_catalog.pg_type t
    JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
    JOIN pg_catalog.pg_class c ON c.oid = t.typrelid
    JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid
    WHERE t.typtype = 'c'
      AND c.relkind = 'c'
      AND a.attnum > 0
      AND NOT a.attisdropped
      AND n.nspname !~ '^pg_'
      AND n.nspname != 'information_schema'
  };

  my @bind;
  if ($filter && @$filter) {
    $sql .= ' AND n.nspname = ANY($1)';
    push @bind, $filter;
  }

  $sql .= ' ORDER BY n.nspname, t.typname, a.attnum';

  my $sth = $dbh->prepare($sql);
  $sth->execute(@bind);

  while (my $row = $sth->fetchrow_hashref) {
    my $key = "$row->{schema_name}.$row->{type_name}";
    $types->{$key} //= {
      schema_name => $row->{schema_name},
      type_name   => $row->{type_name},
      type_kind   => 'composite',
      attributes  => [],
    };
    push @{ $types->{$key}{attributes} }, {
      name    => $row->{attr_name},
      type    => $row->{attr_type},
      ordinal => $row->{ordinal},
    };
  }
}

sub _fetch_ranges {
  my ($class, $dbh, $filter, $types) = @_;

  my $sql = q{
    SELECT
      n.nspname AS schema_name,
      t.typname AS type_name,
      pg_catalog.format_type(r.rngsubtype, NULL) AS subtype
    FROM pg_catalog.pg_type t
    JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
    JOIN pg_catalog.pg_range r ON r.rngtypid = t.oid
    WHERE n.nspname !~ '^pg_'
      AND n.nspname != 'information_schema'
  };

  my @bind;
  if ($filter && @$filter) {
    $sql .= ' AND n.nspname = ANY($1)';
    push @bind, $filter;
  }

  $sql .= ' ORDER BY n.nspname, t.typname';

  my $sth = $dbh->prepare($sql);
  $sth->execute(@bind);

  while (my $row = $sth->fetchrow_hashref) {
    my $key = "$row->{schema_name}.$row->{type_name}";
    $types->{$key} = {
      schema_name => $row->{schema_name},
      type_name   => $row->{type_name},
      type_kind   => 'range',
      subtype     => $row->{subtype},
    };
  }
}

1;
