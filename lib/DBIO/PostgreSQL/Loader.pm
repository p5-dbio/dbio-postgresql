package DBIO::PostgreSQL::Loader;
# ABSTRACT: PostgreSQL introspection for DBIO::Loader

use strict;
use warnings;
use base 'DBIO::Loader::DBI::Component::QuotedDefault';
use mro 'c3';

use DBIO::Loader::Table ();
use DBIO::PostgreSQL::Introspect;
use DBIO::PostgreSQL::Loader::Model;

=head1 DESCRIPTION

This is the PostgreSQL-specific Loader implementation used by L<DBIO::Loader>.
It builds on L<DBIO::PostgreSQL::Introspect> so schema loading, comments,
indexes, triggers, views, and RLS metadata all come from the same native
introspection model.

For the public loader interface, see L<DBIO::Loader> and
L<DBIO::Loader::Base>.

=cut

sub _setup {
  my $self = shift;

  $self->next::method(@_);

  $self->{db_schema} ||= ['public'];

  if ( not defined $self->preserve_case ) {
    $self->preserve_case(0);
  }
  elsif ( $self->preserve_case ) {
    $self->schema->storage->sql_maker->quote_char('"');
    $self->schema->storage->sql_maker->name_sep('.');
  }

  $self->{components} ||= [];
  push @{ $self->{components} }, 'PostgreSQL::Result'
    unless grep { ($_ =~ /^\+?DBIO::PostgreSQL::Result\z/) || $_ eq 'PostgreSQL::Result' } @{ $self->{components} };
}

sub _system_schemas {
  my $self = shift;

  return ( $self->next::method(@_), 'pg_catalog' );
}

sub _loader_model {
  my ($self) = @_;

  return $self->{_loader_model} if $self->{_loader_model};

  my $schema_filter = $self->db_schema;
  $schema_filter = undef
    if !$schema_filter || grep { $_ eq '%' } @$schema_filter;

  my $model = DBIO::PostgreSQL::Introspect->new(
    dbh           => $self->dbh,
    schema_filter => $schema_filter,
  )->model;

  return $self->{_loader_model} = DBIO::PostgreSQL::Loader::Model->new(
    model         => $model,
    preserve_case => $self->preserve_case ? 1 : 0,
    db_schema     => $self->db_schema,
  );
}

sub _table_key {
  my ($self, $table) = @_;
  return join '.', grep { defined && length } ($table->schema, $table->name);
}

sub _tables_list {
  my ($self) = @_;

  return map {
    my ($schema, $name) = split /\./, $_, 2;
    DBIO::Loader::Table->new(
      loader => $self,
      name   => $name,
      schema => $schema,
    )
  } @{ $self->_loader_model->table_keys };
}

sub _table_columns {
  my ($self, $table) = @_;
  return $self->_loader_model->table_columns($self->_table_key($table));
}

sub _table_pk_info {
  my ($self, $table) = @_;
  return $self->_loader_model->table_pk_info($self->_table_key($table));
}

sub _table_uniq_info {
  my ($self, $table) = @_;
  return $self->_loader_model->table_uniq_info($self->_table_key($table));
}

sub _table_fk_info {
  my ($self, $table) = @_;

  return [
    map {
      +{
        %$_,
        remote_table => DBIO::Loader::Table->new(
          loader => $self,
          name   => $_->{remote_table},
          schema => $_->{remote_schema},
        ),
      }
    } @{ $self->_loader_model->table_fk_info($self->_table_key($table)) }
  ];
}

sub _table_comment {
  my ($self, $table) = @_;
  return $self->_loader_model->table_comment($self->_table_key($table));
}

sub _column_comment {
  my ($self, $table, undef, $column_name) = @_;
  return $self->_loader_model->column_comment($self->_table_key($table), $column_name);
}

sub _columns_info_for {
  my ($self, $table) = @_;
  return $self->_loader_model->table_columns_info($self->_table_key($table));
}

sub _table_is_view {
  my ($self, $table) = @_;
  return $self->_loader_model->table_is_view($self->_table_key($table));
}

sub _view_definition {
  my ($self, $table) = @_;
  return $self->_loader_model->view_definition($self->_table_key($table));
}

sub _setup_src_meta {
  my ($self, $table) = @_;

  $self->next::method(@_);

  my $table_class = $self->classes->{$table->sql_name};
  my $table_key   = $self->_table_key($table);

  $self->_dbic_stmt($table_class, 'pg_schema', $table->schema)
    if defined $table->schema && length $table->schema;

  my $pg_indexes = $self->_loader_model->table_pg_indexes($table_key);
  for my $name (sort keys %$pg_indexes) {
    $self->_dbic_stmt($table_class, 'pg_index', $name, $pg_indexes->{$name});
  }

  my $pg_triggers = $self->_loader_model->table_pg_triggers($table_key);
  for my $name (sort keys %$pg_triggers) {
    $self->_dbic_stmt($table_class, 'pg_trigger', $name, $pg_triggers->{$name});
  }

  if (my $pg_rls = $self->_loader_model->table_pg_rls($table_key)) {
    $self->_dbic_stmt($table_class, 'pg_rls', $pg_rls);
  }
}

=head1 SEE ALSO

L<DBIO::Loader>, L<DBIO::Loader::Base>,
L<DBIO::Loader::DBI>

=cut

1;
