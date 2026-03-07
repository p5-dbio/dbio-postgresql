package DBIO::PostgreSQL::Diff::Schema;
# ABSTRACT: Diff operations for PostgreSQL schemas

use strict;
use warnings;

use Moo;
use namespace::clean;

has action => ( is => 'ro', required => 1 ); # create, drop
has schema_name => ( is => 'ro', required => 1 );

sub diff {
  my ($class, $source, $target) = @_;
  my @ops;

  for my $name (sort keys %$target) {
    next if exists $source->{$name};
    push @ops, $class->new(action => 'create', schema_name => $name);
  }

  for my $name (sort keys %$source) {
    next if exists $target->{$name};
    push @ops, $class->new(action => 'drop', schema_name => $name);
  }

  return @ops;
}

sub as_sql {
  my ($self) = @_;
  if ($self->action eq 'create') {
    return sprintf 'CREATE SCHEMA %s;',
      _quote_ident($self->schema_name);
  }
  elsif ($self->action eq 'drop') {
    return sprintf 'DROP SCHEMA %s CASCADE;',
      _quote_ident($self->schema_name);
  }
}

sub summary {
  my ($self) = @_;
  return sprintf '%s schema: %s', ($self->action eq 'create' ? '+' : '-'), $self->schema_name;
}

sub _quote_ident {
  my ($name) = @_;
  return $name if $name =~ /^[a-z_][a-z0-9_]*$/;
  $name =~ s/"/""/g;
  return qq{"$name"};
}

1;
