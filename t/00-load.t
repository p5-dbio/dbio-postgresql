use strict;
use warnings;
use Test::More;

my @modules = qw(
  DBIO::PostgreSQL
  DBIO::PostgreSQL::PgSchema
  DBIO::PostgreSQL::Result
  DBIO::PostgreSQL::Introspect
  DBIO::PostgreSQL::Introspect::Schemas
  DBIO::PostgreSQL::Introspect::Tables
  DBIO::PostgreSQL::Introspect::Columns
  DBIO::PostgreSQL::Introspect::Types
  DBIO::PostgreSQL::Introspect::Indexes
  DBIO::PostgreSQL::Introspect::Triggers
  DBIO::PostgreSQL::Introspect::Functions
  DBIO::PostgreSQL::Introspect::Extensions
  DBIO::PostgreSQL::Introspect::Policies
  DBIO::PostgreSQL::Introspect::Sequences
  DBIO::PostgreSQL::Introspect::ForeignKeys
  DBIO::PostgreSQL::Diff
  DBIO::PostgreSQL::Diff::Schema
  DBIO::PostgreSQL::Diff::Table
  DBIO::PostgreSQL::Diff::Column
  DBIO::PostgreSQL::Diff::Type
  DBIO::PostgreSQL::Diff::Index
  DBIO::PostgreSQL::Diff::Function
  DBIO::PostgreSQL::Diff::Trigger
  DBIO::PostgreSQL::Diff::Policy
  DBIO::PostgreSQL::Diff::Extension
  DBIO::PostgreSQL::DDL
  DBIO::PostgreSQL::Deploy
  DBIO::PostgreSQL::Storage
  DBIO::PostgreSQL::Loader
  DBIO::PostgreSQL::Loader::Model
);

plan tests => scalar @modules;

for my $mod (@modules) {
  use_ok($mod);
}
