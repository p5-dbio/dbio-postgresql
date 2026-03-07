package DBIO::PostgreSQL::Storage;
# ABSTRACT: PostgreSQL storage layer for DBIO

use strict;
use warnings;

use base qw/DBIO::Storage::DBI/;

__PACKAGE__->register_driver('Pg' => __PACKAGE__);

use Scope::Guard ();
use Context::Preserve 'preserve_context';
use DBIO::Carp;
use Try::Tiny;
use namespace::clean;

# PostgreSQL defaults
__PACKAGE__->sql_limit_dialect('LimitOffset');
__PACKAGE__->sql_quote_char('"');
__PACKAGE__->datetime_parser_type('DateTime::Format::Pg');
__PACKAGE__->_use_multicolumn_in(1);

sub _determine_supports_insert_returning {
  return shift->_server_info->{normalized_dbms_version} >= 8.002
    ? 1
    : 0
  ;
}

sub with_deferred_fk_checks {
  my ($self, $sub) = @_;

  my $txn_scope_guard = $self->txn_scope_guard;

  $self->_do_query('SET CONSTRAINTS ALL DEFERRED');

  my $sg = Scope::Guard->new(sub {
    $self->_do_query('SET CONSTRAINTS ALL IMMEDIATE');
  });

  return preserve_context { $sub->() } after => sub { $txn_scope_guard->commit };
}

# only used when INSERT ... RETURNING is disabled
sub last_insert_id {
  my ($self, $source, @cols) = @_;

  my @values;
  my $col_info = $source->columns_info(\@cols);

  for my $col (@cols) {
    my $seq = ( $col_info->{$col}{sequence} ||= $self->dbh_do('_dbh_get_autoinc_seq', $source, $col) )
      or $self->throw_exception( sprintf(
        "Could not determine sequence for column '%s.%s', please consider adding a "
        . "schema-qualified sequence to its column info",
          $source->name,
          $col,
      ));

    push @values, $self->_dbh->last_insert_id(undef, undef, undef, undef, {sequence => $seq});
  }

  return @values;
}

sub _sequence_fetch {
  my ($self, $function, $sequence) = @_;

  $self->throw_exception('No sequence to fetch') unless $sequence;

  my ($val) = $self->_get_dbh->selectrow_array(
    sprintf("select %s('%s')", $function, (ref $sequence eq 'SCALAR') ? $$sequence : $sequence)
  );

  return $val;
}

sub _dbh_get_autoinc_seq {
  my ($self, $dbh, $source, $col) = @_;

  my $schema;
  my $table = $source->name;

  $table = $$table if ref $table eq 'SCALAR';

  if ($table =~ /^(.+)\.(.+)$/) {
    ($schema, $table) = ($1, $2);
  }

  my $seq_expr = $self->_dbh_get_column_default($dbh, $schema, $table, $col);

  unless (defined $seq_expr and $seq_expr =~ /^nextval\(+'([^']+)'::(?:text|regclass)\)/i) {
    $seq_expr = '' unless defined $seq_expr;
    $self->throw_exception( sprintf(
      "No sequence found for '%s%s.%s', check the RDBMS table definition or explicitly set the "
      . "'sequence' for this column in %s",
        $schema ? "$schema." : '',
        $table,
        $col,
        $source->source_name,
    ));
  }

  return $1;
}

sub _dbh_get_column_default {
  my ($self, $dbh, $schema, $table, $col) = @_;

  my $sqlmaker = $self->sql_maker;
  local $sqlmaker->{bindtype} = 'normal';

  my ($where, @bind) = $sqlmaker->where({
    'a.attnum'  => {'>', 0},
    'c.relname' => $table,
    'a.attname' => $col,
    -not_bool   => 'a.attisdropped',
    (defined $schema && length $schema)
      ? ('n.nspname' => $schema)
      : (-bool => \'pg_catalog.pg_table_is_visible(c.oid)')
  });

  my ($seq_expr) = $dbh->selectrow_array(<<"EOS", undef, @bind);

SELECT
  (SELECT pg_catalog.pg_get_expr(d.adbin, d.adrelid)
   FROM pg_catalog.pg_attrdef d
   WHERE d.adrelid = a.attrelid AND d.adnum = a.attnum AND a.atthasdef)
FROM pg_catalog.pg_class c
     LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
     JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid
$where

EOS

  return $seq_expr;
}

sub sqlt_type { 'PostgreSQL' }

sub _explain_sql { "EXPLAIN ANALYZE $_[1]" }

sub _minmax_operator_for_datatype {
  #my ($self, $datatype, $want_max) = @_;

  return ($_[2] ? 'BOOL_OR' : 'BOOL_AND')
    if ($_[1] || '') =~ /\Abool(?:ean)?\z/i;

  shift->next::method(@_);
}

sub bind_attribute_by_data_type {
  my ($self, $data_type) = @_;

  if ($self->_is_binary_lob_type($data_type)) {
    unless ($DBD::Pg::__DBIO_DBD_VERSION_CHECK_DONE__) {
      if ($self->_server_info->{normalized_dbms_version} >= 9.0) {
        try { DBD::Pg->VERSION('2.17.2'); 1 } or carp(
          __PACKAGE__ . ': BYTEA columns are known to not work on Pg >= 9.0 with DBD::Pg < 2.17.2'
        );
      }
      elsif (not try { DBD::Pg->VERSION('2.9.2'); 1 }) { carp(
        __PACKAGE__ . ': DBD::Pg 2.9.2 or greater is strongly recommended for BYTEA column support'
      )}

      $DBD::Pg::__DBIO_DBD_VERSION_CHECK_DONE__ = 1;
    }

    return { pg_type => DBD::Pg::PG_BYTEA() };
  }
  else {
    return undef;
  }
}

# Savepoints via DBD::Pg native methods
sub _exec_svp_begin {
  my ($self, $name) = @_;
  $self->_dbh->pg_savepoint($name);
}

sub _exec_svp_release {
  my ($self, $name) = @_;
  $self->_dbh->pg_release($name);
}

sub _exec_svp_rollback {
  my ($self, $name) = @_;
  $self->_dbh->pg_rollback_to($name);
}

# Override deployment to use DBIO::PostgreSQL::DDL instead of SQL::Translator
sub deploy {
  my ($self, $schema, $type, $sqltargs, $dir) = @_;

  if ($schema->can('pg_deploy')) {
    $schema->pg_deploy->install;
    return;
  }

  # Fallback to parent (SQL::Translator) for schemas without PostgreSQL component
  $self->next::method($schema, $type, $sqltargs, $dir);
}

sub deployment_statements {
  my $self = shift;
  my ($schema, $type, $version, $dir, $sqltargs, @rest) = @_;

  # If schema has PostgreSQL component, generate native DDL
  if ($schema->can('pg_install_ddl')) {
    return $schema->pg_install_ddl;
  }

  # Fallback to SQL::Translator
  $sqltargs ||= {};

  if (
    ! exists $sqltargs->{producer_args}{postgres_version}
      and
    my $dver = $self->_server_info->{normalized_dbms_version}
  ) {
    $sqltargs->{producer_args}{postgres_version} = $dver;
  }

  $self->next::method($schema, $type, $version, $dir, $sqltargs, @rest);
}

1;
