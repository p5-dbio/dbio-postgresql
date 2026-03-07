package DBIO::PostgreSQL::Deploy;
# ABSTRACT: Deploy and upgrade PostgreSQL schemas via test-deploy-and-compare

use strict;
use warnings;

use Moo;
use DBI;
use DBIO::PostgreSQL::DDL;
use DBIO::PostgreSQL::Introspect;
use DBIO::PostgreSQL::Diff;
use namespace::clean;

has schema => (
  is       => 'ro',
  required => 1,
);

has temp_db_prefix => (
  is      => 'ro',
  default => '_dbio_tmp_',
);

sub install {
  my ($self) = @_;
  my $ddl = DBIO::PostgreSQL::DDL->install_ddl($self->schema);
  my $dbh = $self->_dbh;

  for my $stmt (_split_statements($ddl)) {
    $dbh->do($stmt);
  }

  return 1;
}

sub diff {
  my ($self) = @_;

  my $dbh = $self->_dbh;
  my $temp_db = $self->_create_temp_db($dbh);

  my $source_model = eval {
    $self->_introspect_current;
  };
  my $err_source = $@;

  my $target_model = eval {
    $self->_deploy_and_introspect_temp($temp_db);
  };
  my $err_target = $@;

  # Always clean up temp db
  eval { $self->_drop_temp_db($dbh, $temp_db) };

  die $err_source if $err_source;
  die $err_target if $err_target;

  return DBIO::PostgreSQL::Diff->new(
    source => $source_model,
    target => $target_model,
  );
}

sub apply {
  my ($self, $diff) = @_;
  return unless $diff->has_changes;

  my $dbh = $self->_dbh;
  for my $stmt (_split_statements($diff->as_sql)) {
    $dbh->do($stmt);
  }

  return 1;
}

sub upgrade {
  my ($self) = @_;
  my $diff = $self->diff;
  return unless $diff->has_changes;
  $self->apply($diff);
  return $diff;
}

sub install_schema {
  my ($self, $schema_name) = @_;
  my $dbh = $self->_dbh;
  $dbh->do(sprintf 'CREATE SCHEMA IF NOT EXISTS %s', _quote_ident($schema_name));
  return 1;
}

# --- Internal methods ---

sub _dbh {
  my ($self) = @_;
  return $self->schema->storage->dbh;
}

sub _schema_filter {
  my ($self) = @_;
  my @schemas = $self->schema->pg_schemas;
  return @schemas ? \@schemas : undef;
}

sub _introspect_current {
  my ($self) = @_;
  my $intro = DBIO::PostgreSQL::Introspect->new(
    dbh           => $self->_dbh,
    schema_filter => $self->_schema_filter,
  );
  return $intro->model;
}

sub _create_temp_db {
  my ($self, $dbh) = @_;
  my $name = $self->temp_db_prefix . $$ . '_' . time();
  $dbh->do("COMMIT") if $dbh->{AutoCommit} == 0;
  # CREATE DATABASE cannot run inside a transaction
  local $dbh->{AutoCommit} = 1;
  $dbh->do(sprintf 'CREATE DATABASE %s', _quote_ident($name));
  return $name;
}

sub _drop_temp_db {
  my ($self, $dbh, $name) = @_;
  local $dbh->{AutoCommit} = 1;
  $dbh->do(sprintf 'DROP DATABASE IF EXISTS %s', _quote_ident($name));
}

sub _deploy_and_introspect_temp {
  my ($self, $temp_db) = @_;

  # Connect to temp database using same connection info but different dbname
  my $dsn = $self->_temp_dsn($temp_db);
  my $temp_dbh = DBI->connect($dsn, undef, undef, {
    RaiseError => 1,
    AutoCommit => 1,
  }) or die "Cannot connect to temp database: $DBI::errstr";

  eval {
    my $ddl = DBIO::PostgreSQL::DDL->install_ddl($self->schema);
    for my $stmt (_split_statements($ddl)) {
      $temp_dbh->do($stmt);
    }
  };
  my $deploy_err = $@;

  my $model;
  unless ($deploy_err) {
    eval {
      my $intro = DBIO::PostgreSQL::Introspect->new(
        dbh           => $temp_dbh,
        schema_filter => $self->_schema_filter,
      );
      $model = $intro->model;
    };
    $deploy_err = $@ unless $model;
  }

  $temp_dbh->disconnect;

  die $deploy_err if $deploy_err;
  return $model;
}

sub _temp_dsn {
  my ($self, $temp_db) = @_;
  my $storage = $self->schema->storage;
  my @connect_info = @{ $storage->connect_info };
  my $dsn = $connect_info[0];

  if (ref $dsn eq 'CODE') {
    die "DBIO::PostgreSQL::Deploy does not support coderef DSN for temp database connections";
  }

  # Replace dbname in DSN
  if ($dsn =~ /dbname=/) {
    $dsn =~ s/dbname=[^;]+/dbname=$temp_db/;
  } else {
    $dsn .= ";dbname=$temp_db";
  }

  return $dsn;
}

sub _split_statements {
  my ($sql) = @_;
  my @stmts;
  # Split on semicolons that are not inside dollar-quoted strings
  my $in_dollar = 0;
  my $current = '';

  for my $line (split /\n/, $sql) {
    if ($line =~ /\$\$/) {
      my $count = () = $line =~ /\$\$/g;
      $in_dollar = ($in_dollar + $count) % 2;
    }
    $current .= "$line\n";

    if (!$in_dollar && $line =~ /;\s*$/) {
      $current =~ s/^\s+|\s+$//g;
      push @stmts, $current if $current =~ /\S/;
      $current = '';
    }
  }

  $current =~ s/^\s+|\s+$//g;
  push @stmts, $current if $current =~ /\S/;

  return @stmts;
}

sub _quote_ident {
  my ($name) = @_;
  return $name if $name =~ /^[a-z_][a-z0-9_]*$/;
  $name =~ s/"/""/g;
  return qq{"$name"};
}

1;
