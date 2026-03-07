package DBIO::PostgreSQL::Diff;
# ABSTRACT: Compare two introspected PostgreSQL models

use strict;
use warnings;

use Moo;
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

has target => (
  is       => 'ro',
  required => 1,
);

has operations => (
  is      => 'lazy',
  builder => '_build_operations',
);

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

sub has_changes {
  my ($self) = @_;
  return scalar @{ $self->operations } > 0;
}

sub as_sql {
  my ($self) = @_;
  return join "\n", map { $_->as_sql } @{ $self->operations };
}

sub summary {
  my ($self) = @_;
  return join "\n", map { $_->summary } @{ $self->operations };
}

1;
