package DBIO::PostgreSQL::Introspect;
# ABSTRACT: Introspect a PostgreSQL database via pg_catalog

use strict;
use warnings;

use Moo;
use DBIO::PostgreSQL::Introspect::Schemas;
use DBIO::PostgreSQL::Introspect::Tables;
use DBIO::PostgreSQL::Introspect::Columns;
use DBIO::PostgreSQL::Introspect::Types;
use DBIO::PostgreSQL::Introspect::Indexes;
use DBIO::PostgreSQL::Introspect::Triggers;
use DBIO::PostgreSQL::Introspect::Functions;
use DBIO::PostgreSQL::Introspect::Extensions;
use DBIO::PostgreSQL::Introspect::Policies;
use DBIO::PostgreSQL::Introspect::Sequences;
use namespace::clean;

has dbh => (
  is       => 'ro',
  required => 1,
);

has schema_filter => (
  is      => 'ro',
  default => sub { undef },
);

has model => (
  is      => 'lazy',
  builder => '_build_model',
);

sub _build_model {
  my ($self) = @_;
  my $dbh = $self->dbh;
  my $filter = $self->schema_filter;

  my $schemas    = DBIO::PostgreSQL::Introspect::Schemas->fetch($dbh, $filter);
  my $extensions = DBIO::PostgreSQL::Introspect::Extensions->fetch($dbh);
  my $types      = DBIO::PostgreSQL::Introspect::Types->fetch($dbh, $filter);
  my $tables     = DBIO::PostgreSQL::Introspect::Tables->fetch($dbh, $filter);
  my $columns    = DBIO::PostgreSQL::Introspect::Columns->fetch($dbh, $filter);
  my $indexes    = DBIO::PostgreSQL::Introspect::Indexes->fetch($dbh, $filter);
  my $triggers   = DBIO::PostgreSQL::Introspect::Triggers->fetch($dbh, $filter);
  my $functions  = DBIO::PostgreSQL::Introspect::Functions->fetch($dbh, $filter);
  my $policies   = DBIO::PostgreSQL::Introspect::Policies->fetch($dbh, $filter);
  my $sequences  = DBIO::PostgreSQL::Introspect::Sequences->fetch($dbh, $filter);

  return {
    schemas    => $schemas,
    extensions => $extensions,
    types      => $types,
    tables     => $tables,
    columns    => $columns,
    indexes    => $indexes,
    triggers   => $triggers,
    functions  => $functions,
    policies   => $policies,
    sequences  => $sequences,
  };
}

1;
