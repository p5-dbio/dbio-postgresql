package DBIO::PostgreSQL::Diff::Function;
# ABSTRACT: Diff operations for PostgreSQL functions

use strict;
use warnings;

use Moo;
use namespace::clean;

has action => ( is => 'ro', required => 1 ); # create, drop, replace
has function_key => ( is => 'ro', required => 1 );
has function_info => ( is => 'ro' );

sub diff {
  my ($class, $source, $target) = @_;
  my @ops;

  for my $key (sort keys %$target) {
    if (!exists $source->{$key}) {
      push @ops, $class->new(
        action        => 'create',
        function_key  => $key,
        function_info => $target->{$key},
      );
      next;
    }
    # Compare definitions
    my $src_def = $source->{$key}{definition} // '';
    my $tgt_def = $target->{$key}{definition} // '';
    if ($src_def ne $tgt_def) {
      push @ops, $class->new(
        action        => 'replace',
        function_key  => $key,
        function_info => $target->{$key},
      );
    }
  }

  for my $key (sort keys %$source) {
    next if exists $target->{$key};
    push @ops, $class->new(
      action        => 'drop',
      function_key  => $key,
      function_info => $source->{$key},
    );
  }

  return @ops;
}

sub as_sql {
  my ($self) = @_;
  my $info = $self->function_info;

  if ($self->action eq 'create' || $self->action eq 'replace') {
    if ($info->{definition}) {
      my $def = $info->{definition};
      $def =~ s/\s*$//;
      $def .= ';' unless $def =~ /;\s*$/;
      return $def;
    }
    return sprintf '-- CREATE OR REPLACE FUNCTION %s (definition unavailable)', $self->function_key;
  }
  elsif ($self->action eq 'drop') {
    return sprintf 'DROP FUNCTION %s;', $self->function_key;
  }
}

sub summary {
  my ($self) = @_;
  my $prefix = $self->action eq 'create' ? '+' : $self->action eq 'drop' ? '-' : '~';
  return sprintf '%sfunction: %s', $prefix, $self->function_key;
}

1;
