package DBIO::PostgreSQL::Diff::Extension;
# ABSTRACT: Diff operations for PostgreSQL extensions

use strict;
use warnings;

use Moo;
use namespace::clean;

=head1 DESCRIPTION

Represents an extension-level diff operation: C<CREATE EXTENSION IF NOT
EXISTS>, C<DROP EXTENSION>, or C<ALTER EXTENSION ... UPDATE TO> (version
change). Extensions are compared by name; version differences produce an update
operation.

=cut

has action => ( is => 'ro', required => 1 ); # create, drop, update

=attr action

The operation type: C<create>, C<drop>, or C<update>.

=cut

has extension_name => ( is => 'ro', required => 1 );

=attr extension_name

The PostgreSQL extension name (e.g. C<pgcrypto>, C<postgis>).

=cut

has extension_info => ( is => 'ro' );

=attr extension_info

Extension metadata hashref (C<version>, C<schema_name>, C<relocatable>).

=cut

has old_version => ( is => 'ro' );

=attr old_version

The installed version (set for C<update> operations).

=cut

has new_version => ( is => 'ro' );

=attr new_version

The desired version (set for C<update> operations).

=cut

=method diff

    my @ops = DBIO::PostgreSQL::Diff::Extension->diff($source, $target);

Compares extension hashrefs. Produces C<create>, C<update> (version changed),
or C<drop> operations.

=cut

sub diff {
  my ($class, $source, $target) = @_;
  my @ops;

  for my $name (sort keys %$target) {
    if (!exists $source->{$name}) {
      push @ops, $class->new(
        action         => 'create',
        extension_name => $name,
        extension_info => $target->{$name},
      );
      next;
    }
    # Version changes
    my $src_ver = $source->{$name}{version} // '';
    my $tgt_ver = $target->{$name}{version} // '';
    if ($src_ver ne $tgt_ver) {
      push @ops, $class->new(
        action         => 'update',
        extension_name => $name,
        extension_info => $target->{$name},
        old_version    => $src_ver,
        new_version    => $tgt_ver,
      );
    }
  }

  for my $name (sort keys %$source) {
    next if exists $target->{$name};
    push @ops, $class->new(
      action         => 'drop',
      extension_name => $name,
      extension_info => $source->{$name},
    );
  }

  return @ops;
}

=method as_sql

Returns the SQL for this operation.

=cut

sub as_sql {
  my ($self) = @_;
  if ($self->action eq 'create') {
    return sprintf 'CREATE EXTENSION IF NOT EXISTS %s;', $self->extension_name;
  }
  elsif ($self->action eq 'drop') {
    return sprintf 'DROP EXTENSION %s;', $self->extension_name;
  }
  elsif ($self->action eq 'update') {
    return sprintf "ALTER EXTENSION %s UPDATE TO '%s';",
      $self->extension_name, $self->new_version;
  }
}

=method summary

Returns a one-line description such as C<+extension: pgcrypto> or
C<~extension: postgis (3.3 -E<gt> 3.4)>.

=cut

sub summary {
  my ($self) = @_;
  if ($self->action eq 'update') {
    return sprintf '~extension: %s (%s -> %s)',
      $self->extension_name, $self->old_version, $self->new_version;
  }
  my $prefix = $self->action eq 'create' ? '+' : '-';
  return sprintf '%sextension: %s', $prefix, $self->extension_name;
}

1;
