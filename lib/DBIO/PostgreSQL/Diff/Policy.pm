package DBIO::PostgreSQL::Diff::Policy;
# ABSTRACT: Diff operations for PostgreSQL Row Level Security policies

use strict;
use warnings;

=head1 DESCRIPTION

Represents a Row Level Security diff operation: C<CREATE POLICY>, C<DROP
POLICY>, C<ENABLE ROW LEVEL SECURITY>, or C<DISABLE ROW LEVEL SECURITY>. RLS
enable/disable changes on tables are detected by comparing the C<rls_enabled>
flag from table introspection.

=cut

sub new { my ($class, %args) = @_; bless \%args, $class }

sub action { $_[0]->{action} }

=attr action

The operation type: C<create>, C<drop>, C<enable_rls>, or C<disable_rls>.

=cut

sub table_key { $_[0]->{table_key} }

=attr table_key

The C<schema.table> key identifying the table.

=cut

sub policy_name { $_[0]->{policy_name} }

=attr policy_name

The policy name (not set for C<enable_rls> / C<disable_rls> operations).

=cut

sub policy_info { $_[0]->{policy_info} }

=attr policy_info

Policy metadata hashref (C<command>, C<permissive>, C<using_expr>,
C<check_expr>, C<roles>).

=cut

=method diff

    my @ops = DBIO::PostgreSQL::Diff::Policy->diff(
        $source_pol, $target_pol, $source_tables, $target_tables,
    );

Compares RLS state and policy sets. Detects RLS enable/disable changes on
existing tables, new policies, and dropped policies.

=cut

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

=method as_sql

Returns the SQL for this operation: C<ALTER TABLE ... ENABLE/DISABLE ROW LEVEL
SECURITY>, C<CREATE POLICY ...>, or C<DROP POLICY ... ON ...>.

=cut

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

=method summary

Returns a one-line description such as C<+policy: users_own_data on auth.users>
or C<enable_rls on auth.users>.

=cut

sub summary {
  my ($self) = @_;
  if ($self->action =~ /rls/) {
    return sprintf '  %s RLS on %s', $self->action, $self->table_key;
  }
  my $prefix = $self->action eq 'create' ? '+' : '-';
  return sprintf '  %spolicy: %s on %s', $prefix, $self->policy_name, $self->table_key;
}

1;
