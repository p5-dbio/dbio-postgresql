package DBIO::PostgreSQL::Diff::Trigger;
# ABSTRACT: Diff operations for PostgreSQL triggers

use strict;
use warnings;

use Moo;
use namespace::clean;

has action => ( is => 'ro', required => 1 ); # create, drop
has table_key => ( is => 'ro', required => 1 );
has trigger_name => ( is => 'ro', required => 1 );
has trigger_info => ( is => 'ro' );

sub diff {
  my ($class, $source, $target) = @_;
  my @ops;

  for my $table_key (sort keys %$target) {
    my $src_trgs = $source->{$table_key} // {};
    my $tgt_trgs = $target->{$table_key};

    for my $name (sort keys %$tgt_trgs) {
      if (!exists $src_trgs->{$name}) {
        push @ops, $class->new(
          action       => 'create',
          table_key    => $table_key,
          trigger_name => $name,
          trigger_info => $tgt_trgs->{$name},
        );
        next;
      }
      # Changed: compare definitions
      my $src_def = $src_trgs->{$name}{definition} // '';
      my $tgt_def = $tgt_trgs->{$name}{definition} // '';
      if ($src_def ne $tgt_def) {
        push @ops, $class->new(
          action       => 'drop',
          table_key    => $table_key,
          trigger_name => $name,
          trigger_info => $src_trgs->{$name},
        );
        push @ops, $class->new(
          action       => 'create',
          table_key    => $table_key,
          trigger_name => $name,
          trigger_info => $tgt_trgs->{$name},
        );
      }
    }
  }

  for my $table_key (sort keys %$source) {
    my $src_trgs = $source->{$table_key};
    my $tgt_trgs = $target->{$table_key} // {};

    for my $name (sort keys %$src_trgs) {
      next if exists $tgt_trgs->{$name};
      push @ops, $class->new(
        action       => 'drop',
        table_key    => $table_key,
        trigger_name => $name,
        trigger_info => $src_trgs->{$name},
      );
    }
  }

  return @ops;
}

sub as_sql {
  my ($self) = @_;
  if ($self->action eq 'create') {
    if ($self->trigger_info->{definition}) {
      return $self->trigger_info->{definition} . ';';
    }
    return sprintf '-- CREATE TRIGGER %s ON %s (definition unavailable)',
      $self->trigger_name, $self->table_key;
  }
  elsif ($self->action eq 'drop') {
    return sprintf 'DROP TRIGGER %s ON %s;', $self->trigger_name, $self->table_key;
  }
}

sub summary {
  my ($self) = @_;
  my $prefix = $self->action eq 'create' ? '+' : '-';
  return sprintf '  %strigger: %s on %s', $prefix, $self->trigger_name, $self->table_key;
}

1;
