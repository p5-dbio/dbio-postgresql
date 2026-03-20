package DBIO::PostgreSQL::Diff::Schema;
# ABSTRACT: Diff operations for PostgreSQL schemas

use strict;
use warnings;

=head1 DESCRIPTION

Represents a single schema (namespace) diff operation: C<CREATE SCHEMA> or
C<DROP SCHEMA CASCADE>. Instances are produced by the L</diff> class method
and consumed by L<DBIO::PostgreSQL::Diff>.

=cut

sub new { my ($class, %args) = @_; bless \%args, $class }

sub action { $_[0]->{action} }

=attr action

The operation type: C<create> or C<drop>.

=cut

sub schema_name { $_[0]->{schema_name} }

=attr schema_name

The PostgreSQL schema name being created or dropped.

=cut

=method diff

    my @ops = DBIO::PostgreSQL::Diff::Schema->diff($source, $target);

Compares two schema hashrefs (as from L<DBIO::PostgreSQL::Introspect::Schemas>)
and returns a list of C<DBIO::PostgreSQL::Diff::Schema> objects representing
schemas to create or drop.

=cut

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

=method as_sql

Returns the SQL statement for this operation: C<CREATE SCHEMA name;> or
C<DROP SCHEMA name CASCADE;>.

=cut

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

=method summary

Returns a one-line human-readable description such as C<+schema: auth> or
C<-schema: old_ns>.

=cut

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
