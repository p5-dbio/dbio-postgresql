package DBIO::PostgreSQL::Diff::Extension;
# ABSTRACT: Diff operations for PostgreSQL extensions

use strict;
use warnings;

use Moo;
use namespace::clean;

has action => ( is => 'ro', required => 1 ); # create, drop, update
has extension_name => ( is => 'ro', required => 1 );
has extension_info => ( is => 'ro' );
has old_version => ( is => 'ro' );
has new_version => ( is => 'ro' );

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
