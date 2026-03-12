package DBIO::PostgreSQL::Result;
# ABSTRACT: PostgreSQL-specific Result component for DBIO

use strict;
use warnings;

use base 'DBIO';

__PACKAGE__->mk_classdata('_pg_schema_name');
__PACKAGE__->mk_classdata('_pg_indexes' => {});
__PACKAGE__->mk_classdata('_pg_triggers' => {});
__PACKAGE__->mk_classdata('_pg_rls');

=head1 DESCRIPTION

C<DBIO::PostgreSQL::Result> is a DBIO Result component that adds
PostgreSQL-native metadata to a result class: the PostgreSQL schema
(namespace) the table belongs to, custom indexes, triggers, and Row Level
Security (RLS) configuration.

Load it with:

    package MyApp::DB::Result::User;
    use base 'DBIO::Core';
    __PACKAGE__->load_components('PostgreSQL::Result');

    __PACKAGE__->pg_schema('auth');
    __PACKAGE__->table('users');

The schema name from C<pg_schema> is used by L<DBIO::PostgreSQL::DDL> to
qualify table names (e.g. C<auth.users>) in generated DDL.

=cut

=method pg_schema

    __PACKAGE__->pg_schema('auth');
    my $name = $class->pg_schema;

Get or set the PostgreSQL schema (namespace) for this result class. When set,
L<DBIO::PostgreSQL::DDL> qualifies the table name as C<schema.table> in
generated DDL.

=cut

sub pg_schema {
  my ($class, $name) = @_;
  if (defined $name) {
    $class->_pg_schema_name($name);
  }
  return $class->_pg_schema_name;
}

=method pg_qualified_table

    my $fqn = $class->pg_qualified_table;  # e.g. 'auth.users'

Returns the fully-qualified table name C<schema.table>, or just C<table> if no
PostgreSQL schema has been set.

=cut

sub pg_qualified_table {
  my ($class) = @_;
  my $schema = $class->_pg_schema_name;
  my $table = $class->table;
  return $schema ? "${schema}.${table}" : $table;
}

=method pg_index

    __PACKAGE__->pg_index('idx_users_tags' => {
        using   => 'gin',
        columns => ['tags'],
    });
    __PACKAGE__->pg_index('idx_users_active' => {
        columns => ['role'],
        where   => "role != 'suspended'",
    });
    __PACKAGE__->pg_index('idx_users_embedding' => {
        using   => 'ivfflat',
        columns => ['embedding'],
        with    => { lists => 100 },
    });

    my $def = $class->pg_index('idx_users_tags');

Get or set the definition for a named PostgreSQL index. The definition hashref
accepts:

=over 4

=item C<columns> - ArrayRef of column names

=item C<using> - index access method (C<btree>, C<gin>, C<gist>, C<brin>, C<hash>, C<ivfflat>, etc.)

=item C<where> - partial index predicate (SQL expression string)

=item C<expression> - expression index expression (replaces C<columns>)

=item C<with> - storage parameter hashref (e.g. C<{ lists =E<gt> 100 }> for ivfflat)

=back

=cut

sub pg_index {
  my ($class, $name, $def) = @_;
  if ($def) {
    my $indexes = { %{ $class->_pg_indexes } };
    $indexes->{$name} = $def;
    $class->_pg_indexes($indexes);
  }
  return $class->_pg_indexes->{$name};
}

=method pg_indexes

    my $all = $class->pg_indexes;  # hashref of name => def

Returns a copy of all index definitions registered on this result class.

=cut

sub pg_indexes {
  my ($class) = @_;
  return { %{ $class->_pg_indexes } };
}

=method pg_trigger

    __PACKAGE__->pg_trigger('users_modified_at' => {
        when    => 'BEFORE',
        event   => 'UPDATE',
        execute => 'auth.update_modified_at()',
    });

    my $def = $class->pg_trigger('users_modified_at');

Get or set the definition for a named PostgreSQL trigger. The definition
hashref accepts C<when> (C<BEFORE>/C<AFTER>/C<INSTEAD OF>), C<event>
(C<INSERT>/C<UPDATE>/C<DELETE>/C<TRUNCATE>), and C<execute> (the function to
call).

=cut

sub pg_trigger {
  my ($class, $name, $def) = @_;
  if ($def) {
    my $triggers = { %{ $class->_pg_triggers } };
    $triggers->{$name} = $def;
    $class->_pg_triggers($triggers);
  }
  return $class->_pg_triggers->{$name};
}

=method pg_triggers

    my $all = $class->pg_triggers;  # hashref of name => def

Returns a copy of all trigger definitions registered on this result class.

=cut

sub pg_triggers {
  my ($class) = @_;
  return { %{ $class->_pg_triggers } };
}

=method pg_rls

    __PACKAGE__->pg_rls({
        enable   => 1,
        force    => 1,
        policies => {
            users_own_data => {
                for   => 'ALL',
                using => 'id = current_setting($$app.current_user_id$$)::uuid',
            },
        },
    });

    my $rls = $class->pg_rls;

Get or set the Row Level Security configuration for this table. The hashref
accepts:

=over 4

=item C<enable> - boolean, generates C<ENABLE ROW LEVEL SECURITY>

=item C<force> - boolean, generates C<FORCE ROW LEVEL SECURITY>

=item C<policies> - hashref of policy name to policy definition (C<for>, C<using>, C<with_check>)

=back

=cut

sub pg_rls {
  my ($class, $def) = @_;
  if ($def) {
    $class->_pg_rls($def);
  }
  return $class->_pg_rls;
}

=seealso

=over 4

=item * L<DBIO::PostgreSQL> - the schema component (Database layer)

=item * L<DBIO::PostgreSQL::PgSchema> - the PgSchema layer for enums, types, functions

=item * L<DBIO::PostgreSQL::DDL> - generates DDL from result class metadata

=back

=cut

1;
