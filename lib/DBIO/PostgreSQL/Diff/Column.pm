package DBIO::PostgreSQL::Diff::Column;
# ABSTRACT: Diff operations for PostgreSQL columns

use strict;
use warnings;

=head1 DESCRIPTION

Represents a column-level diff operation: C<ADD COLUMN>, C<DROP COLUMN>, or
C<ALTER COLUMN> (type change, nullability change, or default change). Only
columns on tables that exist in both source and target are compared.

=cut

sub new { my ($class, %args) = @_; bless \%args, $class }

sub action { $_[0]->{action} }

=attr action

The operation type: C<add>, C<drop>, or C<alter>.

=cut

sub table_key { $_[0]->{table_key} }

=attr table_key

The C<schema.table> key identifying which table the column belongs to.

=cut

sub column_name { $_[0]->{column_name} }

=attr column_name

The column name.

=cut

sub old_info { $_[0]->{old_info} }

=attr old_info

The source column metadata hashref (present for C<drop> and C<alter>).

=cut

sub new_info { $_[0]->{new_info} }

=attr new_info

The target column metadata hashref (present for C<add> and C<alter>).

=cut

=method diff

    my @ops = DBIO::PostgreSQL::Diff::Column->diff(
        $source_cols, $target_cols, $source_tables, $target_tables,
    );

Compares column lists for tables that exist in both source and target.
Detects added columns, dropped columns, and altered columns (data type,
C<NOT NULL>, or default value changes).

=cut

sub diff {
  my ($class, $source_cols, $target_cols, $source_tables, $target_tables) = @_;
  my @ops;

  # Only diff columns for tables that exist in both source and target
  for my $table_key (sort keys %$target_cols) {
    next unless exists $source_tables->{$table_key} && exists $target_tables->{$table_key};

    my %source_by_name = map { $_->{column_name} => $_ } @{ $source_cols->{$table_key} // [] };
    my %target_by_name = map { $_->{column_name} => $_ } @{ $target_cols->{$table_key} // [] };

    # New columns
    for my $col_name (sort keys %target_by_name) {
      next if exists $source_by_name{$col_name};
      push @ops, $class->new(
        action      => 'add',
        table_key   => $table_key,
        column_name => $col_name,
        new_info    => $target_by_name{$col_name},
      );
    }

    # Dropped columns
    for my $col_name (sort keys %source_by_name) {
      next if exists $target_by_name{$col_name};
      push @ops, $class->new(
        action      => 'drop',
        table_key   => $table_key,
        column_name => $col_name,
        old_info    => $source_by_name{$col_name},
      );
    }

    # Altered columns
    for my $col_name (sort keys %target_by_name) {
      next unless exists $source_by_name{$col_name};
      my $src = $source_by_name{$col_name};
      my $tgt = $target_by_name{$col_name};

      my $changed = 0;
      $changed = 1 if ($src->{data_type} // '') ne ($tgt->{data_type} // '');
      $changed = 1 if ($src->{not_null} // 0) != ($tgt->{not_null} // 0);
      $changed = 1 if ($src->{default_value} // '') ne ($tgt->{default_value} // '');

      next unless $changed;
      push @ops, $class->new(
        action      => 'alter',
        table_key   => $table_key,
        column_name => $col_name,
        old_info    => $src,
        new_info    => $tgt,
      );
    }
  }

  return @ops;
}

=method as_sql

Returns one or more C<ALTER TABLE> statements for this operation. For C<alter>,
may return multiple statements (one per changed attribute).

=cut

sub as_sql {
  my ($self) = @_;
  if ($self->action eq 'add') {
    my $type = $self->new_info->{data_type};
    my $sql = sprintf 'ALTER TABLE %s ADD COLUMN %s %s',
      $self->table_key, $self->column_name, $type;
    $sql .= ' NOT NULL' if $self->new_info->{not_null};
    if (defined $self->new_info->{default_value}) {
      $sql .= sprintf ' DEFAULT %s', $self->new_info->{default_value};
    }
    return "$sql;";
  }
  elsif ($self->action eq 'drop') {
    return sprintf 'ALTER TABLE %s DROP COLUMN %s;',
      $self->table_key, $self->column_name;
  }
  elsif ($self->action eq 'alter') {
    my @stmts;
    my $src = $self->old_info;
    my $tgt = $self->new_info;

    if (($src->{data_type} // '') ne ($tgt->{data_type} // '')) {
      push @stmts, sprintf 'ALTER TABLE %s ALTER COLUMN %s TYPE %s;',
        $self->table_key, $self->column_name, $tgt->{data_type};
    }
    if (($src->{not_null} // 0) != ($tgt->{not_null} // 0)) {
      if ($tgt->{not_null}) {
        push @stmts, sprintf 'ALTER TABLE %s ALTER COLUMN %s SET NOT NULL;',
          $self->table_key, $self->column_name;
      } else {
        push @stmts, sprintf 'ALTER TABLE %s ALTER COLUMN %s DROP NOT NULL;',
          $self->table_key, $self->column_name;
      }
    }
    if (($src->{default_value} // '') ne ($tgt->{default_value} // '')) {
      if (defined $tgt->{default_value} && $tgt->{default_value} ne '') {
        push @stmts, sprintf 'ALTER TABLE %s ALTER COLUMN %s SET DEFAULT %s;',
          $self->table_key, $self->column_name, $tgt->{default_value};
      } else {
        push @stmts, sprintf 'ALTER TABLE %s ALTER COLUMN %s DROP DEFAULT;',
          $self->table_key, $self->column_name;
      }
    }
    return join "\n", @stmts;
  }
}

=method summary

Returns a one-line description such as C<+column: auth.users.avatar (text)>.

=cut

sub summary {
  my ($self) = @_;
  my $prefix = $self->action eq 'add' ? '+' : $self->action eq 'drop' ? '-' : '~';
  my $type = $self->new_info ? " ($self->{new_info}{data_type})" : '';
  return sprintf '  %scolumn: %s.%s%s', $prefix, $self->table_key, $self->column_name, $type;
}

1;
