requires 'perl', '5.020';

requires 'DBIO';
requires 'DBI';
requires 'DBD::Pg';
requires 'Moo';
requires 'namespace::clean';
requires 'Types::Standard';

on test => sub {
  requires 'Test::More', '0.98';
  requires 'Test::Exception';
  requires 'Test::Warn';
  requires 'Test::Fatal';
  requires 'Sub::Name';
  requires 'Try::Tiny';
  requires 'DBIO::Test';
};
