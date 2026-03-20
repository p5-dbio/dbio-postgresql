package DBIO::PostgreSQL::Test::SequenceTest;
# ABSTRACT: Test result class for PostgreSQL sequence tests
our $VERSION = '0.900000';

use strict;
use warnings;

use base qw/DBIO::Test::BaseResult/;

__PACKAGE__->table('sequence_test');

__PACKAGE__->add_columns(
  pkid1 => {
    data_type => 'integer',
    sequence => 'pkid1_seq',
    is_auto_increment => 1,
    auto_nextval => 1,
  },
  pkid2 => {
    data_type => 'integer',
    sequence => 'pkid2_seq',
    is_auto_increment => 1,
    auto_nextval => 1,
  },
  nonpkid => {
    data_type => 'integer',
    sequence => 'nonpkid_seq',
    is_auto_increment => 1,
    auto_nextval => 1,
  },
  name => {
    data_type => 'varchar',
    size => 100,
    is_nullable => 1,
  },
);

__PACKAGE__->set_primary_key('pkid1', 'pkid2');

1;
