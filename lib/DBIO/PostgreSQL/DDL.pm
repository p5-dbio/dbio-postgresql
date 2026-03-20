package DBIO::PostgreSQL::DDL;
# ABSTRACT: Generate PostgreSQL DDL from DBIO schema classes

use strict;
use warnings;

=head1 DESCRIPTION

C<DBIO::PostgreSQL::DDL> generates PostgreSQL DDL statements directly from
DBIO schema and result classes, without going through SQL::Translator. This
produces correct, PostgreSQL-native SQL that preserves all PostgreSQL-specific
features.

The generated DDL is used by L<DBIO::PostgreSQL::Deploy/install> for fresh
installs and by the test-deploy side of L<DBIO::PostgreSQL::Deploy/diff> for
upgrade diffing. Reach for this class directly when you want the raw SQL text;
use L<DBIO::PostgreSQL::Deploy> when you want database orchestration.

=cut

=method install_ddl

    my $sql = DBIO::PostgreSQL::DDL->install_ddl($schema);

Generates a complete PostgreSQL DDL script for the connected schema object.
The script is ordered to satisfy dependencies:

=over 4

=item 1. C<CREATE EXTENSION IF NOT EXISTS> statements

=item 2. C<CREATE SCHEMA IF NOT EXISTS> statements (skipping C<public>)

=item 3. Enum types, composite types, and functions from L<DBIO::PostgreSQL::PgSchema> subclasses

=item 4. C<CREATE TABLE> statements with columns, primary keys, indexes, triggers, and RLS from L<DBIO::PostgreSQL::Result> classes

=item 5. C<ALTER DATABASE CURRENT SET> for C<pg_settings>

=item 6. C<SET search_path TO> from C<pg_search_path>

=back

Returns the DDL as a single string with statements separated by blank lines.

=cut

sub install_ddl {
  my ($class, $schema) = @_;
  my @stmts;

  # 1. Extensions
  for my $ext ($schema->pg_extensions) {
    push @stmts, "CREATE EXTENSION IF NOT EXISTS \"$ext\";";
  }

  # 2. Schemas (namespaces)
  for my $ns ($schema->pg_schemas) {
    next if $ns eq 'public'; # public always exists
    push @stmts, sprintf 'CREATE SCHEMA IF NOT EXISTS %s;', _quote_ident($ns);
  }

  # 3. Types from PgSchema classes
  for my $ns ($schema->pg_schemas) {
    my $pg_schema_class = $schema->pg_schema_class($ns);
    next unless $pg_schema_class;

    # Enums
    if ($pg_schema_class->can('_pg_enum_defs')) {
      no strict 'refs';
      for my $def (@{ ${"${pg_schema_class}::_pg_enum_defs"} // [] }) {
        my ($name, $values) = @$def;
        my $vals = join ', ', map { "'$_'" } @$values;
        push @stmts, sprintf "CREATE TYPE %s.%s AS ENUM (%s);",
          _quote_ident($ns), _quote_ident($name), $vals;
      }
    }

    # Composite types
    if ($pg_schema_class->can('_pg_type_defs')) {
      no strict 'refs';
      for my $def (@{ ${"${pg_schema_class}::_pg_type_defs"} // [] }) {
        my ($name, $fields) = @$def;
        my @attrs;
        for my $fname (sort keys %$fields) {
          push @attrs, sprintf '  %s %s', _quote_ident($fname), $fields->{$fname};
        }
        push @stmts, sprintf "CREATE TYPE %s.%s AS (\n%s\n);",
          _quote_ident($ns), _quote_ident($name), join(",\n", @attrs);
      }
    }

    # Functions
    if ($pg_schema_class->can('_pg_function_defs')) {
      no strict 'refs';
      for my $def (@{ ${"${pg_schema_class}::_pg_function_defs"} // [] }) {
        my ($name, $sql) = @$def;
        $sql =~ s/^\s+|\s+$//g;
        $sql .= ';' unless $sql =~ /;\s*$/;
        push @stmts, $sql;
      }
    }
  }

  # 4. Tables from Result classes
  my @sources = $schema->sources;
  for my $source_name (sort @sources) {
    my $source = $schema->source($source_name);
    my $result_class = $source->result_class;

    my $table_name = $source->name;
    my $pg_schema_name;
    if ($result_class->can('pg_schema')) {
      $pg_schema_name = $result_class->pg_schema;
    }

    my $qualified = $pg_schema_name
      ? "$pg_schema_name.$table_name"
      : $table_name;

    # Column definitions
    my @col_defs;
    for my $col_name ($source->columns) {
      my $info = $source->column_info($col_name);
      my $type = _pg_column_type($info);
      my $def = sprintf '  %s %s', _quote_ident($col_name), $type;
      $def .= ' NOT NULL' if $info->{is_nullable} && !$info->{is_nullable};
      $def .= ' NOT NULL' if defined $info->{is_nullable} && !$info->{is_nullable};
      if (defined $info->{default_value}) {
        my $dv = $info->{default_value};
        if (ref $dv eq 'SCALAR') {
          $def .= " DEFAULT $$dv";
        } else {
          $def .= " DEFAULT '$dv'";
        }
      }
      push @col_defs, $def;
    }

    # Primary key
    my @pk = $source->primary_columns;
    if (@pk) {
      push @col_defs, sprintf '  PRIMARY KEY (%s)',
        join(', ', map { _quote_ident($_) } @pk);
    }

    push @stmts, sprintf "CREATE TABLE %s (\n%s\n);",
      $qualified, join(",\n", @col_defs);

    # PostgreSQL-specific indexes
    if ($result_class->can('pg_indexes')) {
      my $indexes = $result_class->pg_indexes;
      for my $idx_name (sort keys %$indexes) {
        my $idx = $indexes->{$idx_name};
        my $using = $idx->{using} ? " USING $idx->{using}" : '';
        my $columns;
        if ($idx->{expression}) {
          $columns = $idx->{expression};
        } else {
          $columns = join(', ', @{ $idx->{columns} // [] });
        }
        my $unique = $idx->{unique} ? 'UNIQUE ' : '';
        my $sql = sprintf 'CREATE %sINDEX %s ON %s%s (%s)',
          $unique, _quote_ident($idx_name), $qualified, $using, $columns;
        if ($idx->{with}) {
          my @with_parts;
          for my $k (sort keys %{ $idx->{with} }) {
            push @with_parts, "$k = $idx->{with}{$k}";
          }
          $sql .= ' WITH (' . join(', ', @with_parts) . ')';
        }
        $sql .= " WHERE $idx->{where}" if $idx->{where};
        push @stmts, "$sql;";
      }
    }

    # Triggers
    if ($result_class->can('pg_triggers')) {
      my $triggers = $result_class->pg_triggers;
      for my $trg_name (sort keys %$triggers) {
        my $trg = $triggers->{$trg_name};
        my $for_each = $trg->{for_each} || 'ROW';
        push @stmts, sprintf 'CREATE TRIGGER %s %s %s ON %s FOR EACH %s EXECUTE FUNCTION %s;',
          _quote_ident($trg_name), $trg->{when}, $trg->{event},
          $qualified, $for_each, $trg->{execute};
      }
    }

    # RLS
    if ($result_class->can('pg_rls') && $result_class->pg_rls) {
      my $rls = $result_class->pg_rls;
      if ($rls->{enable}) {
        push @stmts, sprintf 'ALTER TABLE %s ENABLE ROW LEVEL SECURITY;', $qualified;
      }
      if ($rls->{force}) {
        push @stmts, sprintf 'ALTER TABLE %s FORCE ROW LEVEL SECURITY;', $qualified;
      }
      if ($rls->{policies}) {
        for my $pol_name (sort keys %{ $rls->{policies} }) {
          my $pol = $rls->{policies}{$pol_name};
          my $sql = sprintf 'CREATE POLICY %s ON %s',
            _quote_ident($pol_name), $qualified;
          $sql .= sprintf ' FOR %s', $pol->{for} if $pol->{for} && $pol->{for} ne 'ALL';
          if ($pol->{roles} && @{ $pol->{roles} }) {
            $sql .= sprintf ' TO %s', join(', ', @{ $pol->{roles} });
          }
          $sql .= sprintf ' USING (%s)', $pol->{using} if $pol->{using};
          $sql .= sprintf ' WITH CHECK (%s)', $pol->{with_check} if $pol->{with_check};
          push @stmts, "$sql;";
        }
      }
    }
  }

  # 5. Settings
  my $settings = $schema->pg_settings;
  if ($settings && %$settings) {
    for my $key (sort keys %$settings) {
      push @stmts, sprintf "ALTER DATABASE CURRENT SET %s = '%s';",
        $key, $settings->{$key};
    }
  }

  # 6. Search path
  my @search_path = $schema->pg_search_path;
  if (@search_path) {
    push @stmts, sprintf "SET search_path TO %s;",
      join(', ', @search_path);
  }

  return join("\n\n", @stmts) . "\n";
}

=seealso

=over 4

=item * L<DBIO::PostgreSQL> - schema component that calls C<pg_install_ddl>

=item * L<DBIO::PostgreSQL::Deploy> - uses C<install_ddl> for fresh installs and diff

=item * L<DBIO::PostgreSQL::PgSchema> - source of enum, type, and function definitions

=item * L<DBIO::PostgreSQL::Result> - source of table, index, trigger, and RLS definitions

=back

=cut

sub _pg_column_type {
  my ($info) = @_;
  my $type = $info->{data_type};

  # Handle enum types
  if ($type eq 'enum' && $info->{pg_enum_type}) {
    return $info->{pg_enum_type};
  }

  # Handle composite types
  if ($type eq 'composite' && $info->{pg_type_name}) {
    return $info->{pg_type_name};
  }

  # Handle arrays
  return $type if $type =~ /\[\]$/;

  # Handle parameterized types (varchar(N), numeric(P,S), vector(N))
  return $type if $type =~ /\(.+\)$/;

  # Map common DBIO types to PG types
  my %type_map = (
    integer           => 'integer',
    bigint            => 'bigint',
    smallint          => 'smallint',
    serial            => 'serial',
    bigserial         => 'bigserial',
    text              => 'text',
    varchar           => 'character varying',
    char              => 'character',
    boolean           => 'boolean',
    float             => 'double precision',
    real              => 'real',
    numeric           => 'numeric',
    date              => 'date',
    timestamp         => 'timestamp without time zone',
    'timestamp with time zone' => 'timestamp with time zone',
    timestamptz       => 'timestamp with time zone',
    uuid              => 'uuid',
    json              => 'json',
    jsonb             => 'jsonb',
    bytea             => 'bytea',
    inet              => 'inet',
    cidr              => 'cidr',
    macaddr           => 'macaddr',
    tsvector          => 'tsvector',
    tsquery           => 'tsquery',
    xml               => 'xml',
    money             => 'money',
    interval          => 'interval',
    point             => 'point',
    line              => 'line',
    lseg              => 'lseg',
    box               => 'box',
    path              => 'path',
    polygon           => 'polygon',
    circle            => 'circle',
  );

  return $type_map{$type} // $type;
}

sub _quote_ident {
  my ($name) = @_;
  return $name if $name =~ /^[a-z_][a-z0-9_]*$/;
  $name =~ s/"/""/g;
  return qq{"$name"};
}

1;
