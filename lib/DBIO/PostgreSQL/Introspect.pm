package DBIO::PostgreSQL::Introspect;
# ABSTRACT: Introspect a PostgreSQL database via pg_catalog

use strict;
use warnings;

=head1 DESCRIPTION

C<DBIO::PostgreSQL::Introspect> reads the live state of a PostgreSQL database
via C<pg_catalog> and returns a unified model hashref. It is the source side
of the test-deploy-and-compare strategy used by L<DBIO::PostgreSQL::Deploy>.

    my $intro = DBIO::PostgreSQL::Introspect->new(
        dbh           => $dbh,
        schema_filter => [qw( public auth api )],
    );
    my $model = $intro->model;
    # $model->{schemas}, $model->{tables}, $model->{columns}, ...

The model is built lazily on first access and covers schemas, extensions,
types (enums/composites/ranges), tables, columns, indexes, triggers,
functions, RLS policies, and sequences. The same model shape is consumed by
L<DBIO::PostgreSQL::Diff> and by the test-deploy workflow in
L<DBIO::PostgreSQL::Deploy>.

=cut

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
use DBIO::PostgreSQL::Introspect::ForeignKeys;

sub new { my ($class, %args) = @_; bless \%args, $class }

sub dbh { $_[0]->{dbh} }

=attr dbh

A connected C<DBI> database handle. Required.

=cut

sub schema_filter { $_[0]->{schema_filter} }

=attr schema_filter

Optional ArrayRef of PostgreSQL schema names to restrict introspection to.
When C<undef>, all non-system schemas are introspected.

=cut

sub model { $_[0]->{model} //= $_[0]->_build_model }

=attr model

The introspected database model as a hashref. Built lazily on first access.
Keys: C<schemas>, C<extensions>, C<types>, C<tables>, C<columns>, C<indexes>,
C<triggers>, C<functions>, C<policies>, C<sequences>, C<foreign_keys>.

=cut

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
  my $foreign_keys = DBIO::PostgreSQL::Introspect::ForeignKeys->fetch($dbh, $filter);

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
    foreign_keys => $foreign_keys,
  };
}

=seealso

=over 4

=item * L<DBIO::PostgreSQL::Deploy> - uses this class to compare current and desired state

=item * L<DBIO::PostgreSQL::Diff> - compares two models produced by this class

=item * L<DBIO::PostgreSQL::Introspect::Schemas>

=item * L<DBIO::PostgreSQL::Introspect::Tables>

=item * L<DBIO::PostgreSQL::Introspect::Columns>

=item * L<DBIO::PostgreSQL::Introspect::Types>

=item * L<DBIO::PostgreSQL::Introspect::Indexes>

=item * L<DBIO::PostgreSQL::Introspect::Triggers>

=item * L<DBIO::PostgreSQL::Introspect::Functions>

=item * L<DBIO::PostgreSQL::Introspect::Extensions>

=item * L<DBIO::PostgreSQL::Introspect::Policies>

=item * L<DBIO::PostgreSQL::Introspect::Sequences>

=item * L<DBIO::PostgreSQL::Introspect::ForeignKeys>

=back

=cut

1;
