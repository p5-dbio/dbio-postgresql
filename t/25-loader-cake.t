use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;

my ($dsn, $user, $pass) = @ENV{map { "DBIOTEST_PG_$_" } qw(DSN USER PASS)};

plan skip_all => 'Set DBIOTEST_PG_DSN, _USER and _PASS to run this test'
    unless $dsn;

eval { require DBIO::Loader }
    or plan skip_all => 'DBIO::Loader required';

use DBI;

my $tmpdir = tempdir(CLEANUP => 1);

my $dbh = DBI->connect($dsn, $user, $pass, { RaiseError => 1 });

# Create a test schema with PG-specific types
$dbh->do('DROP SCHEMA IF EXISTS dbio_loader_cake CASCADE');
$dbh->do('CREATE SCHEMA dbio_loader_cake');
$dbh->do("SET search_path TO dbio_loader_cake");

# Enum type
$dbh->do("CREATE TYPE dbio_loader_cake.status_type AS ENUM ('active', 'inactive', 'suspended')");

# Table with PG-specific column types
$dbh->do('CREATE TABLE dbio_loader_cake.app_user (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name VARCHAR(128) NOT NULL,
    email VARCHAR(256) NOT NULL,
    status dbio_loader_cake.status_type DEFAULT \'active\' NOT NULL,
    tags TEXT[] DEFAULT \'{}\',
    metadata JSONB DEFAULT \'{}\',
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE (email)
)');

$dbh->do('CREATE TABLE dbio_loader_cake.post (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES dbio_loader_cake.app_user(id),
    title VARCHAR(512) NOT NULL,
    body TEXT,
    published BOOLEAN DEFAULT false
)');

# pgvector if available
my $has_vector = eval {
    $dbh->do('CREATE EXTENSION IF NOT EXISTS vector SCHEMA dbio_loader_cake');
    $dbh->do('ALTER TABLE dbio_loader_cake.app_user ADD COLUMN embedding vector(3)');
    1;
};

$dbh->disconnect;

sub _slurp { open my $fh, '<', $_[0] or die "Cannot read $_[0]: $!"; local $/; <$fh> }

# --- Cake style with PG features ---

my $cake_dir = File::Spec->catdir($tmpdir, 'cake');
mkdir $cake_dir;

my $pid = fork();
die "fork: $!" unless defined $pid;
if (!$pid) {
    DBIO::Loader::make_schema_at('TestPgCake::Schema', {
        dump_directory => $cake_dir,
        quiet          => 1,
        generate_pod   => 0,
        naming         => 'current',
        loader_style   => 'cake',
        db_schema      => ['dbio_loader_cake'],
    }, [$dsn, $user, $pass]);
    exit 0;
}
waitpid($pid, 0);
is($? >> 8, 0, 'Cake schema generated');

my $rd = "$cake_dir/TestPgCake/Schema/Result";

ok -f "$rd/AppUser.pm", 'app_user table found';
ok -f "$rd/Post.pm",    'post table found';

my $user_file = _slurp("$rd/AppUser.pm");

# Cake header
like $user_file, qr/use DBIO::Cake/,
    'uses DBIO::Cake';

# UUID column
like $user_file, qr/^col id => uuid/m,
    'uuid column type in Cake DSL';

# Enum column
like $user_file, qr/col status/,
    'status enum column present';

# Array column
like $user_file, qr/col tags/,
    'array column present';

# JSONB column
like $user_file, qr/col metadata/,
    'jsonb column present';

# Timestamp
like $user_file, qr/col created_at/,
    'timestamptz column present';

# pgvector
SKIP: {
    skip 'pgvector extension not available', 1 unless $has_vector;
    like $user_file, qr/col embedding => vector\(3\)/,
        'pgvector column with dimensions in Cake DSL';
}

# Relationships
my $post = _slurp("$rd/Post.pm");
like $post, qr/^belongs_to /m,
    'post belongs_to user';

# Vanilla style for comparison
my $vanilla_dir = File::Spec->catdir($tmpdir, 'vanilla');
mkdir $vanilla_dir;

$pid = fork();
die "fork: $!" unless defined $pid;
if (!$pid) {
    DBIO::Loader::make_schema_at('TestPgVanilla::Schema', {
        dump_directory => $vanilla_dir,
        quiet          => 1,
        generate_pod   => 0,
        naming         => 'current',
        db_schema      => ['dbio_loader_cake'],
    }, [$dsn, $user, $pass]);
    exit 0;
}
waitpid($pid, 0);
is($? >> 8, 0, 'Vanilla schema generated');

my $vanilla_user = _slurp("$vanilla_dir/TestPgVanilla/Schema/Result/AppUser.pm");

# PG-specific types preserved in vanilla
like $vanilla_user, qr/data_type.*"uuid"/s,
    'vanilla: uuid type preserved';
like $vanilla_user, qr/data_type.*"jsonb"/s,
    'vanilla: jsonb type preserved';

# Cleanup
$dbh = DBI->connect($dsn, $user, $pass, { RaiseError => 1 });
$dbh->do('DROP SCHEMA IF EXISTS dbio_loader_cake CASCADE');
$dbh->disconnect;

done_testing;
