package DBIO::PostgreSQL::Diff::Type;
# ABSTRACT: Diff operations for PostgreSQL types (enums, composites, ranges)

use strict;
use warnings;

use Moo;
use namespace::clean;

has action => ( is => 'ro', required => 1 ); # create, drop, add_value
has type_key => ( is => 'ro', required => 1 );
has type_info => ( is => 'ro' );
has added_values => ( is => 'ro' ); # for enum add_value

sub diff {
  my ($class, $source, $target) = @_;
  my @ops;

  for my $key (sort keys %$target) {
    if (!exists $source->{$key}) {
      push @ops, $class->new(
        action    => 'create',
        type_key  => $key,
        type_info => $target->{$key},
      );
      next;
    }

    # Existing type — check for enum value additions
    my $src = $source->{$key};
    my $tgt = $target->{$key};

    if ($tgt->{type_kind} eq 'enum' && $src->{type_kind} eq 'enum') {
      my %src_vals = map { $_ => 1 } @{ $src->{values} };
      my @new_vals = grep { !$src_vals{$_} } @{ $tgt->{values} };
      if (@new_vals) {
        push @ops, $class->new(
          action       => 'add_value',
          type_key     => $key,
          type_info    => $tgt,
          added_values => \@new_vals,
        );
      }
    }
  }

  for my $key (sort keys %$source) {
    next if exists $target->{$key};
    push @ops, $class->new(
      action    => 'drop',
      type_key  => $key,
      type_info => $source->{$key},
    );
  }

  return @ops;
}

sub as_sql {
  my ($self) = @_;
  my $info = $self->type_info;

  if ($self->action eq 'create') {
    if ($info->{type_kind} eq 'enum') {
      my $values = join ', ', map { "'$_'" } @{ $info->{values} };
      return sprintf "CREATE TYPE %s AS ENUM (%s);", $self->type_key, $values;
    }
    elsif ($info->{type_kind} eq 'composite') {
      my $attrs = join ",\n  ", map {
        "$_->{name} $_->{type}"
      } @{ $info->{attributes} };
      return sprintf "CREATE TYPE %s AS (\n  %s\n);", $self->type_key, $attrs;
    }
    elsif ($info->{type_kind} eq 'range') {
      return sprintf "CREATE TYPE %s AS RANGE (SUBTYPE = %s);",
        $self->type_key, $info->{subtype};
    }
  }
  elsif ($self->action eq 'drop') {
    return sprintf "DROP TYPE %s CASCADE;", $self->type_key;
  }
  elsif ($self->action eq 'add_value') {
    return join "\n", map {
      sprintf "ALTER TYPE %s ADD VALUE '%s';", $self->type_key, $_
    } @{ $self->added_values };
  }
}

sub summary {
  my ($self) = @_;
  if ($self->action eq 'add_value') {
    my $count = scalar @{ $self->added_values };
    my $vals = join ', ', @{ $self->added_values };
    return sprintf '  ~type %s: +%d value(s) (%s)', $self->type_key, $count, $vals;
  }
  my $prefix = $self->action eq 'create' ? '+' : '-';
  return sprintf '%stype: %s (%s)', $prefix, $self->type_key, $self->type_info->{type_kind};
}

1;
