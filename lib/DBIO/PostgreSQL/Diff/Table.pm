package DBIO::PostgreSQL::Diff::Table;
# ABSTRACT: Diff operations for PostgreSQL tables
our $VERSION = '0.900000';

use strict;
use warnings;

=head1 DESCRIPTION

Represents a table-level diff operation: C<CREATE TABLE> (empty shell -- columns
are added separately by L<DBIO::PostgreSQL::Diff::Column>) or C<DROP TABLE
CASCADE>. Instances are produced by L</diff> and consumed by
L<DBIO::PostgreSQL::Diff>.

=cut

sub new { my ($class, %args) = @_; bless \%args, $class }

sub action { $_[0]->{action} }

=attr action

The operation type: C<create> or C<drop>.

=cut

sub schema_name { $_[0]->{schema_name} }

=attr schema_name

PostgreSQL schema containing the table.

=cut

sub table_name { $_[0]->{table_name} }

=attr table_name

The table name.

=cut

sub table_info { $_[0]->{table_info} }

=attr table_info

Hashref of table metadata from introspection (C<kind>, C<rls_enabled>, etc.).

=cut

=method diff

    my @ops = DBIO::PostgreSQL::Diff::Table->diff($source, $target);

Compares two table hashrefs (keyed by C<schema.table>) and returns operations
for tables present only in target (create) or only in source (drop).

=cut

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

=method qualified_name

    my $fqn = $op->qualified_name;  # 'auth.users'

Returns the schema-qualified table name.

=cut

sub qualified_name {
  my ($self) = @_;
  return $self->schema_name . '.' . $self->table_name;
}

=method as_sql

Returns the SQL for this operation.

=cut

sub as_sql {
  my ($self) = @_;
  if ($self->action eq 'create') {
    return sprintf 'CREATE TABLE %s ();', $self->qualified_name;
  }
  elsif ($self->action eq 'drop') {
    return sprintf 'DROP TABLE %s CASCADE;', $self->qualified_name;
  }
}

=method summary

Returns a one-line description such as C<+table: auth.users>.

=cut

sub summary {
  my ($self) = @_;
  return sprintf '%s table: %s',
    ($self->action eq 'create' ? '+' : '-'), $self->qualified_name;
}

1;
