package DBIO::PostgreSQL;
# ABSTRACT: PostgreSQL-specific schema management for DBIO

use strict;
use warnings;

use base 'DBIO';

__PACKAGE__->mk_classdata('_pg_schema_classes' => {});
__PACKAGE__->mk_classdata('_pg_extensions' => []);
__PACKAGE__->mk_classdata('_pg_search_path' => ['public']);
__PACKAGE__->mk_classdata('_pg_settings' => {});

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

sub pg_schema_class {
  my ($class, $name, $pg_schema_class) = @_;
  my $classes = { %{ $class->_pg_schema_classes } };
  if ($pg_schema_class) {
    $classes->{$name} = $pg_schema_class;
    $class->_pg_schema_classes($classes);
  }
  return $classes->{$name};
}

sub pg_extensions {
  my $class = shift;
  if (@_) {
    $class->_pg_extensions([@_]);
  }
  return @{ $class->_pg_extensions };
}

sub pg_search_path {
  my $class = shift;
  if (@_) {
    $class->_pg_search_path([@_]);
  }
  return @{ $class->_pg_search_path };
}

sub pg_settings {
  my $class = shift;
  if (@_) {
    $class->_pg_settings($_[0]);
  }
  return $class->_pg_settings;
}

# Set PostgreSQL-native storage when this component is loaded into a schema
sub connection {
  my ($self, @info) = @_;
  $self->storage_type('+DBIO::PostgreSQL::Storage');
  return $self->next::method(@info);
}

sub pg_deploy {
  my ($self, %args) = @_;
  require DBIO::PostgreSQL::Deploy;
  return DBIO::PostgreSQL::Deploy->new(
    schema => $self,
    %args,
  );
}

sub pg_install_ddl {
  my ($self) = @_;
  require DBIO::PostgreSQL::DDL;
  return DBIO::PostgreSQL::DDL->install_ddl($self);
}

1;
