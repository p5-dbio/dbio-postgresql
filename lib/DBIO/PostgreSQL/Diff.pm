package DBIO::PostgreSQL::Diff;
# ABSTRACT: Compare two introspected PostgreSQL models

use strict;
use warnings;

use Moo;

=head1 DESCRIPTION

C<DBIO::PostgreSQL::Diff> compares two introspected PostgreSQL database models
(as produced by L<DBIO::PostgreSQL::Introspect>) and produces a list of
structured diff operations. These operations can then be rendered to SQL or a
human-readable summary.

    my $diff = DBIO::PostgreSQL::Diff->new(
        source => $current_model,
        target => $desired_model,
    );

    if ($diff->has_changes) {
        print $diff->as_sql;
        print $diff->summary;
    }

Diff operations are generated in dependency order: extensions first, then
schemas, types, functions, tables, columns, indexes, triggers, and policies.

=cut

use DBIO::PostgreSQL::Diff::Schema;
use DBIO::PostgreSQL::Diff::Table;
use DBIO::PostgreSQL::Diff::Column;
use DBIO::PostgreSQL::Diff::Type;
use DBIO::PostgreSQL::Diff::Index;
use DBIO::PostgreSQL::Diff::Function;
use DBIO::PostgreSQL::Diff::Trigger;
use DBIO::PostgreSQL::Diff::Policy;
use DBIO::PostgreSQL::Diff::Extension;
use namespace::clean;

has source => (
  is       => 'ro',
  required => 1,
);

=attr source

The current (live) database model hashref as returned by
L<DBIO::PostgreSQL::Introspect/model>. Required.

=cut

has target => (
  is       => 'ro',
  required => 1,
);

=attr target

The desired (deployed from DBIO classes) database model hashref. Required.

=cut

has operations => (
  is      => 'lazy',
  builder => '_build_operations',
);

=attr operations

ArrayRef of diff operation objects (L<DBIO::PostgreSQL::Diff::Schema>,
L<DBIO::PostgreSQL::Diff::Table>, L<DBIO::PostgreSQL::Diff::Column>, etc.).
Built lazily. Each object responds to C<as_sql> and C<summary>.

=cut

sub _build_operations {
  my ($self) = @_;
  my @ops;

  push @ops, DBIO::PostgreSQL::Diff::Extension->diff(
    $self->source->{extensions}, $self->target->{extensions},
  );
  push @ops, DBIO::PostgreSQL::Diff::Schema->diff(
    $self->source->{schemas}, $self->target->{schemas},
  );
  push @ops, DBIO::PostgreSQL::Diff::Type->diff(
    $self->source->{types}, $self->target->{types},
  );
  push @ops, DBIO::PostgreSQL::Diff::Function->diff(
    $self->source->{functions}, $self->target->{functions},
  );
  push @ops, DBIO::PostgreSQL::Diff::Table->diff(
    $self->source->{tables}, $self->target->{tables},
  );
  push @ops, DBIO::PostgreSQL::Diff::Column->diff(
    $self->source->{columns}, $self->target->{columns},
    $self->source->{tables}, $self->target->{tables},
  );
  push @ops, DBIO::PostgreSQL::Diff::Index->diff(
    $self->source->{indexes}, $self->target->{indexes},
  );
  push @ops, DBIO::PostgreSQL::Diff::Trigger->diff(
    $self->source->{triggers}, $self->target->{triggers},
  );
  push @ops, DBIO::PostgreSQL::Diff::Policy->diff(
    $self->source->{policies}, $self->target->{policies},
    $self->source->{tables}, $self->target->{tables},
  );

  return \@ops;
}

=method has_changes

    if ($diff->has_changes) { ... }

Returns true if there is at least one diff operation between source and target.

=cut

sub has_changes {
  my ($self) = @_;
  return scalar @{ $self->operations } > 0;
}

=method as_sql

    my $sql = $diff->as_sql;

Returns all diff operations concatenated as a PostgreSQL SQL migration script.

=cut

sub as_sql {
  my ($self) = @_;
  return join "\n", map { $_->as_sql } @{ $self->operations };
}

=method summary

    my $text = $diff->summary;

Returns a human-readable summary of all changes, one line per operation.
Added items are prefixed with C<+>, removed with C<->, modified with C<~>.

=cut

sub summary {
  my ($self) = @_;
  return join "\n", map { $_->summary } @{ $self->operations };
}

=seealso

=over 4

=item * L<DBIO::PostgreSQL::Deploy> - orchestrates introspection and diff

=item * L<DBIO::PostgreSQL::Introspect> - produces the models being compared

=item * L<DBIO::PostgreSQL::Diff::Schema>

=item * L<DBIO::PostgreSQL::Diff::Table>

=item * L<DBIO::PostgreSQL::Diff::Column>

=item * L<DBIO::PostgreSQL::Diff::Type>

=item * L<DBIO::PostgreSQL::Diff::Index>

=item * L<DBIO::PostgreSQL::Diff::Function>

=item * L<DBIO::PostgreSQL::Diff::Trigger>

=item * L<DBIO::PostgreSQL::Diff::Policy>

=item * L<DBIO::PostgreSQL::Diff::Extension>

=back

=cut

1;
