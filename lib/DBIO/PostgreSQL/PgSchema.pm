package DBIO::PostgreSQL::PgSchema;
# ABSTRACT: Base class for PostgreSQL schema namespaces

use strict;
use warnings;

use Moo;
use namespace::clean;

has pg_schema_name => (
  is       => 'ro',
  required => 1,
);

has _enums => (
  is      => 'ro',
  default => sub { {} },
);

has _types => (
  is      => 'ro',
  default => sub { {} },
);

has _functions => (
  is      => 'ro',
  default => sub { {} },
);

sub pg_enum {
  my ($self, $name, $values) = @_;
  if (ref $self) {
    $self->_enums->{$name} = $values if $values;
    return $self->_enums->{$name};
  }
  # Class method usage for declarative API
  my $class = $self;
  no strict 'refs';
  push @{ ${"${class}::_pg_enum_defs"} }, [ $name, $values ];
}

sub pg_type {
  my ($self, $name, $fields) = @_;
  if (ref $self) {
    $self->_types->{$name} = $fields if $fields;
    return $self->_types->{$name};
  }
  my $class = $self;
  no strict 'refs';
  push @{ ${"${class}::_pg_type_defs"} }, [ $name, $fields ];
}

sub pg_function {
  my ($self, $name, $sql) = @_;
  if (ref $self) {
    $self->_functions->{$name} = $sql if $sql;
    return $self->_functions->{$name};
  }
  my $class = $self;
  no strict 'refs';
  push @{ ${"${class}::_pg_function_defs"} }, [ $name, $sql ];
}

sub pg_enums {
  my ($self) = @_;
  return { %{ $self->_enums } };
}

sub pg_types {
  my ($self) = @_;
  return { %{ $self->_types } };
}

sub pg_functions {
  my ($self) = @_;
  return { %{ $self->_functions } };
}

1;
