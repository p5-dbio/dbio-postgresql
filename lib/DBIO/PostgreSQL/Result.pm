package DBIO::PostgreSQL::Result;
# ABSTRACT: PostgreSQL-specific Result component for DBIO

use strict;
use warnings;

use base 'DBIO';

__PACKAGE__->mk_classdata('_pg_schema_name');
__PACKAGE__->mk_classdata('_pg_indexes' => {});
__PACKAGE__->mk_classdata('_pg_triggers' => {});
__PACKAGE__->mk_classdata('_pg_rls');

sub pg_schema {
  my ($class, $name) = @_;
  if (defined $name) {
    $class->_pg_schema_name($name);
  }
  return $class->_pg_schema_name;
}

sub pg_qualified_table {
  my ($class) = @_;
  my $schema = $class->_pg_schema_name;
  my $table = $class->table;
  return $schema ? "${schema}.${table}" : $table;
}

sub pg_index {
  my ($class, $name, $def) = @_;
  if ($def) {
    my $indexes = { %{ $class->_pg_indexes } };
    $indexes->{$name} = $def;
    $class->_pg_indexes($indexes);
  }
  return $class->_pg_indexes->{$name};
}

sub pg_indexes {
  my ($class) = @_;
  return { %{ $class->_pg_indexes } };
}

sub pg_trigger {
  my ($class, $name, $def) = @_;
  if ($def) {
    my $triggers = { %{ $class->_pg_triggers } };
    $triggers->{$name} = $def;
    $class->_pg_triggers($triggers);
  }
  return $class->_pg_triggers->{$name};
}

sub pg_triggers {
  my ($class) = @_;
  return { %{ $class->_pg_triggers } };
}

sub pg_rls {
  my ($class, $def) = @_;
  if ($def) {
    $class->_pg_rls($def);
  }
  return $class->_pg_rls;
}

1;
