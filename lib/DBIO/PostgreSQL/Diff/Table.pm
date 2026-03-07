package DBIO::PostgreSQL::Diff::Table;
# ABSTRACT: Diff operations for PostgreSQL tables

use strict;
use warnings;

use Moo;
use namespace::clean;

has action => ( is => 'ro', required => 1 ); # create, drop
has schema_name => ( is => 'ro', required => 1 );
has table_name => ( is => 'ro', required => 1 );
has table_info => ( is => 'ro' );

sub diff {
  my ($class, $source, $target) = @_;
  my @ops;

  for my $key (sort keys %$target) {
    next if exists $source->{$key};
    my $t = $target->{$key};
    push @ops, $class->new(
      action      => 'create',
      schema_name => $t->{schema_name},
      table_name  => $t->{table_name},
      table_info  => $t,
    );
  }

  for my $key (sort keys %$source) {
    next if exists $target->{$key};
    my $t = $source->{$key};
    push @ops, $class->new(
      action      => 'drop',
      schema_name => $t->{schema_name},
      table_name  => $t->{table_name},
      table_info  => $t,
    );
  }

  return @ops;
}

sub qualified_name {
  my ($self) = @_;
  return $self->schema_name . '.' . $self->table_name;
}

sub as_sql {
  my ($self) = @_;
  if ($self->action eq 'create') {
    return sprintf 'CREATE TABLE %s ();', $self->qualified_name;
  }
  elsif ($self->action eq 'drop') {
    return sprintf 'DROP TABLE %s CASCADE;', $self->qualified_name;
  }
}

sub summary {
  my ($self) = @_;
  return sprintf '%s table: %s',
    ($self->action eq 'create' ? '+' : '-'), $self->qualified_name;
}

1;
