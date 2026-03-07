package DBIO::PostgreSQL::Diff::Index;
# ABSTRACT: Diff operations for PostgreSQL indexes

use strict;
use warnings;

use Moo;
use namespace::clean;

has action => ( is => 'ro', required => 1 ); # create, drop
has table_key => ( is => 'ro', required => 1 );
has index_name => ( is => 'ro', required => 1 );
has index_info => ( is => 'ro' );

sub diff {
  my ($class, $source, $target) = @_;
  my @ops;

  # Collect all index names across all tables
  my %src_indexes;
  for my $table_key (keys %$source) {
    for my $idx_name (keys %{ $source->{$table_key} }) {
      $src_indexes{$idx_name} = {
        table_key  => $table_key,
        index_info => $source->{$table_key}{$idx_name},
      };
    }
  }

  my %tgt_indexes;
  for my $table_key (keys %$target) {
    for my $idx_name (keys %{ $target->{$table_key} }) {
      $tgt_indexes{$idx_name} = {
        table_key  => $table_key,
        index_info => $target->{$table_key}{$idx_name},
      };
    }
  }

  # New indexes
  for my $name (sort keys %tgt_indexes) {
    if (!exists $src_indexes{$name}) {
      push @ops, $class->new(
        action     => 'create',
        table_key  => $tgt_indexes{$name}{table_key},
        index_name => $name,
        index_info => $tgt_indexes{$name}{index_info},
      );
      next;
    }
    # Changed indexes: compare definitions
    my $src_def = $src_indexes{$name}{index_info}{definition} // '';
    my $tgt_def = $tgt_indexes{$name}{index_info}{definition} // '';
    if ($src_def ne $tgt_def) {
      push @ops, $class->new(
        action     => 'drop',
        table_key  => $src_indexes{$name}{table_key},
        index_name => $name,
        index_info => $src_indexes{$name}{index_info},
      );
      push @ops, $class->new(
        action     => 'create',
        table_key  => $tgt_indexes{$name}{table_key},
        index_name => $name,
        index_info => $tgt_indexes{$name}{index_info},
      );
    }
  }

  # Dropped indexes
  for my $name (sort keys %src_indexes) {
    next if exists $tgt_indexes{$name};
    push @ops, $class->new(
      action     => 'drop',
      table_key  => $src_indexes{$name}{table_key},
      index_name => $name,
      index_info => $src_indexes{$name}{index_info},
    );
  }

  return @ops;
}

sub as_sql {
  my ($self) = @_;
  if ($self->action eq 'create') {
    # Use the full definition from introspection if available
    if ($self->index_info->{definition}) {
      return $self->index_info->{definition} . ';';
    }
    return sprintf 'CREATE INDEX %s ON %s (%s);',
      $self->index_name, $self->table_key,
      join(', ', @{ $self->index_info->{columns} // ['?'] });
  }
  elsif ($self->action eq 'drop') {
    return sprintf 'DROP INDEX %s;', $self->index_name;
  }
}

sub summary {
  my ($self) = @_;
  my $prefix = $self->action eq 'create' ? '+' : '-';
  return sprintf '  %sindex: %s (on %s)', $prefix, $self->index_name, $self->table_key;
}

1;
