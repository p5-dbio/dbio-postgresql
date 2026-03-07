use strict;
use warnings;

use Test::More;
use Test::Warn;
use DBIO::Test;

eval { require DateTime::Format::Pg; 1 }
  or plan skip_all => 'DateTime::Format::Pg not installed';

eval { require DateTime; 1 }
  or plan skip_all => 'DateTime not installed';

my ($dsn, $user, $pass) = @ENV{map { "DBIOTEST_PG_${_}" } qw/DSN USER PASS/};

plan skip_all => 'Set $ENV{DBIOTEST_PG_DSN}, _USER and _PASS to run this test'
  unless ($dsn && $user);

DBIO::Test::Schema->load_classes('EventTZPg');

my $schema = DBIO::Test->init_schema(
  dsn  => $dsn,
  user => $user,
  pass => $pass,
);

# this may generate warnings under certain CI flags, hence do it outside of
# the warnings_are below
my $dt = DateTime->new( year => 2000, time_zone => "America/Chicago" );

warnings_are {
  my $event = $schema->resultset("EventTZPg")->find(1);
  $event->update({created_on => '2009-01-15 17:00:00+00'});
  $event->discard_changes;
  isa_ok($event->created_on, "DateTime") or diag $event->created_on;
  is($event->created_on->time_zone->name, "America/Chicago", "Timezone changed");
  # Time zone difference -> -6hours
  is($event->created_on->iso8601, "2009-01-15T11:00:00", "Time with TZ correct");

# test 'timestamp without time zone'
  my $dt = DateTime->from_epoch(epoch => time);
  $dt->set_nanosecond(int 500_000_000);
  $event->update({ts_without_tz => $dt});
  $event->discard_changes;
  isa_ok($event->ts_without_tz, "DateTime") or diag $event->created_on;
  is($event->ts_without_tz, $dt, 'timestamp without time zone inflation');
  is($event->ts_without_tz->microsecond, $dt->microsecond,
    'timestamp without time zone microseconds survived');
} [], 'No warnings during DT manipulations';

done_testing;
