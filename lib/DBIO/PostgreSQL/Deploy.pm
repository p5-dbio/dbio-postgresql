package DBIO::PostgreSQL::Deploy;
# ABSTRACT: Deploy and upgrade PostgreSQL schemas via test-deploy-and-compare

use strict;
use warnings;

use DBI;
use DBIO::PostgreSQL::DDL;
use DBIO::PostgreSQL::Introspect;
use DBIO::PostgreSQL::Diff;

=head1 DESCRIPTION

C<DBIO::PostgreSQL::Deploy> orchestrates the deployment and upgrade of
PostgreSQL schemas using a test-deploy-and-compare strategy.

For upgrades, instead of computing diffs from abstract class representations,
it:

=over 4

=item 1. Introspects the live database via C<pg_catalog>

=item 2. Creates a temporary database

=item 3. Deploys the desired schema (from DBIO classes) into the temp database

=item 4. Introspects the temp database via C<pg_catalog>

=item 5. Computes the diff between the two models using L<DBIO::PostgreSQL::Diff>

=item 6. Drops the temp database

=back

This means PostgreSQL is comparing with itself — the diff is always accurate
regardless of how complex the schema features are.

The resulting L<DBIO::PostgreSQL::Diff> object is review-friendly as well as
executable: inspect C<summary> when you want a readable change list, or
C<as_sql> when you are ready to apply the ordered migration statements.

    my $deploy = DBIO::PostgreSQL::Deploy->new(
        schema => MyApp::DB->connect($dsn),
    );

    # Fresh install
    $deploy->install;

    # Upgrade (test-deploy + compare + apply)
    $deploy->upgrade;

    # Or in steps:
    my $diff = $deploy->diff;
    print $diff->summary;
    $deploy->apply($diff) if $diff->has_changes;

=cut

sub new {
  my ($class, %args) = @_;
  $args{temp_db_prefix} //= '_dbio_tmp_';
  bless \%args, $class;
}

sub schema { $_[0]->{schema} }

=attr schema

A connected L<DBIO::PostgreSQL> schema instance. Required.

=cut

sub temp_db_prefix { $_[0]->{temp_db_prefix} }

=attr temp_db_prefix

The prefix for temporary database names created during C<diff>. Defaults to
C<_dbio_tmp_>. The full name includes the PID and current timestamp to ensure
uniqueness.

=cut

=method install

    $deploy->install;

Generates DDL from the DBIO schema classes via L<DBIO::PostgreSQL::DDL> and
executes it against the connected database. Suitable for fresh installs on an
empty database.

=cut

sub install {
  my ($self) = @_;
  my $ddl = DBIO::PostgreSQL::DDL->install_ddl($self->schema);
  my $dbh = $self->_dbh;

  for my $stmt (_split_statements($ddl)) {
    $dbh->do($stmt);
  }

  return 1;
}

=method diff

    my $diff = $deploy->diff;

Computes the difference between the current live database and the desired
state defined by the DBIO schema classes. Creates and destroys a temporary
database automatically. Returns a L<DBIO::PostgreSQL::Diff> object.

Note: C<CREATE DATABASE> cannot run inside a transaction, so the connection
must not be in an open transaction.

=cut

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

=method apply

    $deploy->apply($diff);

Applies a L<DBIO::PostgreSQL::Diff> object to the connected database by
executing each SQL statement from C<$diff-E<gt>as_sql> in order. Does nothing
if C<$diff-E<gt>has_changes> is false.

=cut

sub apply {
  my ($self, $diff) = @_;
  return unless $diff->has_changes;

  my $dbh = $self->_dbh;
  for my $stmt (_split_statements($diff->as_sql)) {
    $dbh->do($stmt);
  }

  return 1;
}

=method upgrade

    my $diff = $deploy->upgrade;

Convenience method: calls L</diff> then L</apply>. Returns the
L<DBIO::PostgreSQL::Diff> object if there were changes, or C<undef> if the
database is already up to date.

=cut

sub upgrade {
  my ($self) = @_;
  my $diff = $self->diff;
  return unless $diff->has_changes;
  $self->apply($diff);
  return $diff;
}

=method install_schema

    $deploy->install_schema('tenant_42');

Creates a single PostgreSQL schema (namespace) using C<CREATE SCHEMA IF NOT
EXISTS>. Useful for multi-tenant setups where each tenant gets its own
schema.

=cut

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

=seealso

=over 4

=item * L<DBIO::PostgreSQL> - schema component with C<pg_deploy> factory method

=item * L<DBIO::PostgreSQL::DDL> - generates the DDL used by C<install> and C<diff>

=item * L<DBIO::PostgreSQL::Introspect> - reads the live and temp database state

=item * L<DBIO::PostgreSQL::Diff> - compares the two introspected models

=back

=cut

1;
