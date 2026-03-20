package DBIO::PostgreSQL;
# ABSTRACT: PostgreSQL-specific schema management for DBIO
our $VERSION = '0.900000';

use strict;
use warnings;

use base 'DBIO';

__PACKAGE__->mk_classdata('_pg_schema_classes' => {});
__PACKAGE__->mk_classdata('_pg_extensions' => []);
__PACKAGE__->mk_classdata('_pg_search_path' => ['public']);
__PACKAGE__->mk_classdata('_pg_settings' => {});

=head1 SYNOPSIS

  package MyApp::Schema;
  use base 'DBIO::Schema';
  __PACKAGE__->load_components('DBIO::PostgreSQL');

  # storage_type is set to +DBIO::PostgreSQL::Storage by the component
  my $schema = __PACKAGE__->connect($dsn, $user, $pass);

=head1 DESCRIPTION

L<DBIO::PostgreSQL> is the PostgreSQL driver component for DBIO.

When this component is loaded into a schema class, C<connection()> sets
L<DBIO::Schema/storage_type> to C<+DBIO::PostgreSQL::Storage>, which enables
PostgreSQL-specific storage behavior automatically.

This distribution also provides PostgreSQL-native DDL/deploy helpers and
introspection/diff tooling.

=head1 MIGRATION NOTES

The PostgreSQL storage class was split out of the historical DBIx::Class
monolithic distribution:

=over 4

=item *

Old: C<DBIx::Class::Storage::DBI::Pg>

=item *

New: C<DBIO::PostgreSQL::Storage>

=back

If C<DBIO-PostgreSQL> is installed, core L<DBIO::Storage::DBI> can autodetect
PostgreSQL DSNs and load the new storage class via the driver registry.

=head1 TESTING

Integration tests in this distribution use:

  DBIOTEST_PG_DSN
  DBIOTEST_PG_USER
  DBIOTEST_PG_PASS

SQLMaker-focused tests can run offline via L<DBIO::Test> with:

  storage_type => 'DBIO::PostgreSQL::Storage'

Replicated-path tests can reuse the same harness with:

  replicated   => 1,
  storage_type => 'DBIO::PostgreSQL::Storage'

=head1 METHODS

=method pg_schemas

Get or set the list of PostgreSQL schema names tracked by this schema class.

=cut

sub pg_schemas {
  my $class = shift;
  if (@_) {
    my @schemas = @_;
    $class->_pg_schema_classes({
      map { $_ => undef } @schemas
    });
  }
  return keys %{ $class->_pg_schema_classes };
}

=method pg_schema_class

Get or set the class mapped to a specific PostgreSQL schema name.

=cut

sub pg_schema_class {
  my ($class, $name, $pg_schema_class) = @_;
  my $classes = { %{ $class->_pg_schema_classes } };
  if ($pg_schema_class) {
    $classes->{$name} = $pg_schema_class;
    $class->_pg_schema_classes($classes);
  }
  return $classes->{$name};
}

=method pg_extensions

Get or set PostgreSQL extensions to include during deploy/DDL operations.

=cut

sub pg_extensions {
  my $class = shift;
  if (@_) {
    $class->_pg_extensions([@_]);
  }
  return @{ $class->_pg_extensions };
}

=method pg_search_path

Get or set the default PostgreSQL C<search_path> list.

=cut

sub pg_search_path {
  my $class = shift;
  if (@_) {
    $class->_pg_search_path([@_]);
  }
  return @{ $class->_pg_search_path };
}

=method pg_settings

Get or set additional PostgreSQL settings stored on the schema class.

=cut

sub pg_settings {
  my $class = shift;
  if (@_) {
    $class->_pg_settings($_[0]);
  }
  return $class->_pg_settings;
}

=method connection

Overrides L<DBIO/connection> to force
C<+DBIO::PostgreSQL::Storage> as C<storage_type>.

=cut

sub connection {
  my ($self, @info) = @_;
  $self->storage_type('+DBIO::PostgreSQL::Storage');
  return $self->next::method(@info);
}

=method pg_deploy

Returns a L<DBIO::PostgreSQL::Deploy> instance for the schema.

=cut

sub pg_deploy {
  my ($self, %args) = @_;
  require DBIO::PostgreSQL::Deploy;
  return DBIO::PostgreSQL::Deploy->new(
    schema => $self,
    %args,
  );
}

=method pg_install_ddl

Generates PostgreSQL-native DDL statements for the schema.

=cut

sub pg_install_ddl {
  my ($self) = @_;
  require DBIO::PostgreSQL::DDL;
  return DBIO::PostgreSQL::DDL->install_ddl($self);
}

1;
