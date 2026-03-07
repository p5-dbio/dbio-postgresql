package DBIO::PostgreSQL::Introspect::Triggers;
# ABSTRACT: Introspect PostgreSQL triggers

use strict;
use warnings;

sub fetch {
  my ($class, $dbh, $filter) = @_;

  my $sql = q{
    SELECT
      n.nspname AS schema_name,
      c.relname AS table_name,
      t.tgname AS trigger_name,
      pg_catalog.pg_get_triggerdef(t.oid) AS definition,
      CASE
        WHEN t.tgtype & 2 = 2 THEN 'BEFORE'
        WHEN t.tgtype & 64 = 64 THEN 'INSTEAD OF'
        ELSE 'AFTER'
      END AS timing,
      CASE
        WHEN t.tgtype & 4 = 4 THEN 'INSERT'
        WHEN t.tgtype & 8 = 8 THEN 'DELETE'
        WHEN t.tgtype & 16 = 16 THEN 'UPDATE'
        WHEN t.tgtype & 32 = 32 THEN 'TRUNCATE'
      END AS event,
      CASE WHEN t.tgtype & 1 = 1 THEN 'ROW' ELSE 'STATEMENT' END AS orientation,
      t.tgenabled AS enabled
    FROM pg_catalog.pg_trigger t
    JOIN pg_catalog.pg_class c ON c.oid = t.tgrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE NOT t.tgisinternal
      AND n.nspname !~ '^pg_'
      AND n.nspname != 'information_schema'
  };

  my @bind;
  if ($filter && @$filter) {
    $sql .= ' AND n.nspname = ANY($1)';
    push @bind, $filter;
  }

  $sql .= ' ORDER BY n.nspname, c.relname, t.tgname';

  my $sth = $dbh->prepare($sql);
  $sth->execute(@bind);

  my %triggers;
  while (my $row = $sth->fetchrow_hashref) {
    my $table_key = "$row->{schema_name}.$row->{table_name}";
    $triggers{$table_key}{ $row->{trigger_name} } = {
      trigger_name => $row->{trigger_name},
      definition   => $row->{definition},
      timing       => $row->{timing},
      event        => $row->{event},
      orientation  => $row->{orientation},
      enabled      => $row->{enabled},
    };
  }

  return \%triggers;
}

1;
