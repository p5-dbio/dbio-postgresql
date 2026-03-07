package DBIO::PostgreSQL::Diff::Policy;
# ABSTRACT: Diff operations for PostgreSQL Row Level Security policies

use strict;
use warnings;

use Moo;
use namespace::clean;

has action => ( is => 'ro', required => 1 ); # create, drop, enable_rls, disable_rls
has table_key => ( is => 'ro', required => 1 );
has policy_name => ( is => 'ro' );
has policy_info => ( is => 'ro' );

sub diff {
  my ($class, $source_pol, $target_pol, $source_tables, $target_tables) = @_;
  my @ops;

  # RLS enable/disable changes on tables
  for my $key (sort keys %$target_tables) {
    next unless exists $source_tables->{$key};
    my $src = $source_tables->{$key};
    my $tgt = $target_tables->{$key};

    if (!$src->{rls_enabled} && $tgt->{rls_enabled}) {
      push @ops, $class->new(
        action    => 'enable_rls',
        table_key => $key,
      );
    }
    elsif ($src->{rls_enabled} && !$tgt->{rls_enabled}) {
      push @ops, $class->new(
        action    => 'disable_rls',
        table_key => $key,
      );
    }
  }

  # Policy diffs
  for my $table_key (sort keys %$target_pol) {
    my $src_pols = $source_pol->{$table_key} // {};
    my $tgt_pols = $target_pol->{$table_key};

    for my $name (sort keys %$tgt_pols) {
      if (!exists $src_pols->{$name}) {
        push @ops, $class->new(
          action      => 'create',
          table_key   => $table_key,
          policy_name => $name,
          policy_info => $tgt_pols->{$name},
        );
      }
    }
  }

  for my $table_key (sort keys %$source_pol) {
    my $src_pols = $source_pol->{$table_key};
    my $tgt_pols = $target_pol->{$table_key} // {};

    for my $name (sort keys %$src_pols) {
      next if exists $tgt_pols->{$name};
      push @ops, $class->new(
        action      => 'drop',
        table_key   => $table_key,
        policy_name => $name,
        policy_info => $src_pols->{$name},
      );
    }
  }

  return @ops;
}

sub as_sql {
  my ($self) = @_;

  if ($self->action eq 'enable_rls') {
    return sprintf 'ALTER TABLE %s ENABLE ROW LEVEL SECURITY;', $self->table_key;
  }
  elsif ($self->action eq 'disable_rls') {
    return sprintf 'ALTER TABLE %s DISABLE ROW LEVEL SECURITY;', $self->table_key;
  }
  elsif ($self->action eq 'create') {
    my $info = $self->policy_info;
    my $sql = sprintf 'CREATE POLICY %s ON %s', $self->policy_name, $self->table_key;
    $sql .= sprintf ' FOR %s', $info->{command} if $info->{command} && $info->{command} ne 'ALL';
    $sql .= sprintf ' USING (%s)', $info->{using_expr} if $info->{using_expr};
    $sql .= sprintf ' WITH CHECK (%s)', $info->{check_expr} if $info->{check_expr};
    return "$sql;";
  }
  elsif ($self->action eq 'drop') {
    return sprintf 'DROP POLICY %s ON %s;', $self->policy_name, $self->table_key;
  }
}

sub summary {
  my ($self) = @_;
  if ($self->action =~ /rls/) {
    return sprintf '  %s RLS on %s', $self->action, $self->table_key;
  }
  my $prefix = $self->action eq 'create' ? '+' : '-';
  return sprintf '  %spolicy: %s on %s', $prefix, $self->policy_name, $self->table_key;
}

1;
