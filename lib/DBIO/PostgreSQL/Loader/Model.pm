package DBIO::PostgreSQL::Loader::Model;
# ABSTRACT: Translate PostgreSQL introspection into DBIO::Loader metadata

use strict;
use warnings;

sub new {
  my ($class, %args) = @_;
  $args{preserve_case} //= 0;
  bless \%args, $class;
}

sub model { $_[0]->{model} }
sub preserve_case { $_[0]->{preserve_case} }
sub db_schema { $_[0]->{db_schema} }

sub table_keys {
  my ($self) = @_;
  return [
    sort grep { $self->_include_table($_) }
    keys %{ $self->model->{tables} || {} }
  ];
}

sub table_columns {
  my ($self, $table_key) = @_;
  return [
    map { $self->_normalize_name($_->{column_name}) }
    sort { $a->{ordinal} <=> $b->{ordinal} }
    @{ $self->model->{columns}{$table_key} || [] }
  ];
}

sub table_columns_info {
  my ($self, $table_key) = @_;

  my %pk = map { $_ => 1 } @{ $self->table_pk_info($table_key) };
  my %columns;

  for my $column (
    sort { $a->{ordinal} <=> $b->{ordinal} }
    @{ $self->model->{columns}{$table_key} || [] }
  ) {
    my $name = $self->_normalize_name($column->{column_name});
    my $info = {
      is_nullable => $column->{not_null} ? 0 : 1,
    };

    $self->_normalize_data_type($info, $column);
    $self->_normalize_default_value($info, $column->{default_value}, $pk{$name});

    if ($column->{identity}) {
      $info->{is_auto_increment} = 1;
      $info->{extra}{identity} = $column->{identity};
      $info->{retrieve_on_insert} = 1 if $pk{$name};
    }

    if ($column->{generated}) {
      $info->{extra}{generated} = $column->{generated};
    }

    $columns{$name} = $info;
  }

  return \%columns;
}

sub table_pk_info {
  my ($self, $table_key) = @_;

  my $indexes = $self->model->{indexes}{$table_key} || {};
  for my $name (sort keys %$indexes) {
    my $index = $indexes->{$name};
    next unless $index->{is_primary};
    return [ map { $self->_normalize_name($_) } @{ $index->{columns} || [] } ];
  }

  return [];
}

sub table_uniq_info {
  my ($self, $table_key) = @_;

  my $indexes = $self->model->{indexes}{$table_key} || {};
  my @uniqs;

  for my $name (sort keys %$indexes) {
    my $index = $indexes->{$name};
    next unless $index->{is_unique};
    next if $index->{is_primary};
    next if $index->{predicate};
    next if $index->{expressions};
    next unless @{ $index->{columns} || [] };
    next if ($index->{access_method} || '') ne 'btree';

    push @uniqs, [
      $name => [ map { $self->_normalize_name($_) } @{ $index->{columns} } ],
    ];
  }

  return \@uniqs;
}

sub table_fk_info {
  my ($self, $table_key) = @_;

  my @fks = map {
    {
      _constraint_name => $_->{constraint_name},
      local_columns    => [ map { $self->_normalize_name($_) } @{ $_->{local_columns} || [] } ],
      remote_columns   => [ map { $self->_normalize_name($_) } @{ $_->{remote_columns} || [] } ],
      remote_schema    => $_->{remote_schema},
      remote_table     => $_->{remote_table},
      attrs            => {
        is_deferrable => $_->{is_deferrable} ? 1 : 0,
        on_delete     => $_->{on_delete},
        on_update     => $_->{on_update},
      },
    }
  } @{ $self->model->{foreign_keys}{$table_key} || [] };

  return \@fks;
}

sub table_pg_indexes {
  my ($self, $table_key) = @_;

  my $indexes = $self->model->{indexes}{$table_key} || {};
  my %pg_indexes;

  for my $name (sort keys %$indexes) {
    my $index = $indexes->{$name};
    next if $index->{is_primary};

    my $simple_unique = $index->{is_unique}
      && !$index->{predicate}
      && !$index->{expressions}
      && @{ $index->{columns} || [] }
      && ($index->{access_method} || '') eq 'btree';

    next if $simple_unique;

    my %def;
    $def{columns}    = [ map { $self->_normalize_name($_) } @{ $index->{columns} } ]
      if @{ $index->{columns} || [] };
    $def{expression} = $index->{expressions} if $index->{expressions};
    $def{where}      = $index->{predicate} if $index->{predicate};
    $def{using}      = $index->{access_method}
      if ($index->{access_method} || '') ne 'btree';
    $def{unique}     = 1 if $index->{is_unique};

    $pg_indexes{$name} = \%def if %def;
  }

  return \%pg_indexes;
}

sub table_pg_triggers {
  my ($self, $table_key) = @_;

  my $triggers = $self->model->{triggers}{$table_key} || {};
  my %defs;

  for my $name (sort keys %$triggers) {
    my $trigger = $triggers->{$name};
    my ($execute) = ($trigger->{definition} || '') =~ /\bEXECUTE\s+FUNCTION\s+(.+?)\s*;?\s*\z/i;
    $defs{$name} = {
      when     => $trigger->{timing},
      event    => $trigger->{event},
      for_each => $trigger->{orientation},
      ($execute ? (execute => $execute) : ()),
    };
  }

  return \%defs;
}

sub table_pg_rls {
  my ($self, $table_key) = @_;

  my $table    = $self->model->{tables}{$table_key} || {};
  my $policies = $self->model->{policies}{$table_key} || {};

  return undef unless $table->{rls_enabled} || $table->{rls_forced} || keys %$policies;

  my %defs;
  for my $name (sort keys %$policies) {
    my $policy = $policies->{$name};
    $defs{$name} = {
      for        => $policy->{command} || 'ALL',
      ($policy->{roles} ? (roles => $self->_normalize_array($policy->{roles})) : ()),
      ($policy->{using_expr} ? (using => $policy->{using_expr}) : ()),
      ($policy->{check_expr} ? (with_check => $policy->{check_expr}) : ()),
    };
  }

  return {
    enable   => $table->{rls_enabled} ? 1 : 0,
    force    => $table->{rls_forced} ? 1 : 0,
    (keys %defs ? (policies => \%defs) : ()),
  };
}

sub table_is_view {
  my ($self, $table_key) = @_;
  my $table = $self->model->{tables}{$table_key} || {};
  return ($table->{kind} || '') =~ /^(?:v|m)\z/ ? 1 : 0;
}

sub view_definition {
  my ($self, $table_key) = @_;
  my $table = $self->model->{tables}{$table_key} || {};
  my $def = $table->{view_definition};
  return undef unless defined $def;
  $def =~ s/^\s+//;
  $def =~ s/\s+\z//;
  $def =~ s/\s*;\s*\z//;
  return $def;
}

sub table_comment {
  my ($self, $table_key) = @_;
  return $self->model->{tables}{$table_key}{comment};
}

sub column_comment {
  my ($self, $table_key, $column_name) = @_;

  for my $column (@{ $self->model->{columns}{$table_key} || [] }) {
    return $column->{comment}
      if $self->_normalize_name($column->{column_name}) eq $self->_normalize_name($column_name);
  }

  return undef;
}

sub _include_table {
  my ($self, $table_key) = @_;
  my ($schema) = split /\./, $table_key, 2;
  my $filter = $self->db_schema;
  return 1 unless $filter && @$filter;
  return 1 if grep { $_ eq '%' } @$filter;
  return scalar grep { $_ eq $schema } @$filter;
}

sub _normalize_name {
  my ($self, $name) = @_;
  return $self->preserve_case ? $name : lc $name;
}

sub _normalize_data_type {
  my ($self, $info, $column) = @_;

  my $type = lc($column->{data_type} || '');

  if ($column->{type_category} && $column->{type_category} eq 'e' && $column->{enum_type}) {
    my $qualified = $column->{type_schema} && $column->{type_schema} ne 'public'
      ? "$column->{type_schema}.$column->{enum_type}"
      : $column->{enum_type};
    my $type_info = $self->model->{types}{$qualified}
      || $self->model->{types}{ ($column->{type_schema} || '') . '.' . $column->{enum_type} };

    $info->{data_type} = 'enum';
    $info->{extra}{list} = $self->_normalize_array($type_info->{values}) if $type_info && $type_info->{values};
    $info->{extra}{custom_type_name} = $qualified;
    $info->{pg_enum_type} = $qualified;
    return;
  }

  if ($type =~ /^(character varying|varchar)\((\d+)\)\z/) {
    $info->{data_type} = 'varchar';
    $info->{size} = 0 + $2;
    return;
  }

  if ($type =~ /^character varying\z/) {
    $info->{data_type} = 'text';
    $info->{original}{data_type} = 'varchar';
    return;
  }

  if ($type =~ /^(character|char)\((\d+)\)\z/) {
    $info->{data_type} = 'char';
    $info->{size} = 0 + $2;
    return;
  }

  if ($type =~ /^(numeric|decimal)\((\d+),(\d+)\)\z/) {
    $info->{data_type} = $1;
    $info->{size} = [ 0 + $2, 0 + $3 ];
    return;
  }

  if ($type =~ /^(bit varying|varbit)\((\d+)\)\z/) {
    $info->{data_type} = 'varbit';
    $info->{size} = 0 + $2;
    return;
  }

  if ($type =~ /^bit\((\d+)\)\z/) {
    $info->{data_type} = 'bit';
    $info->{size} = 0 + $1;
    return;
  }

  if ($type =~ /^(vector|halfvec|sparsevec)\((\d+)\)\z/) {
    $info->{data_type} = $1;
    $info->{size} = 0 + $2;
    return;
  }

  if ($type =~ /^(timestamp|time)\((\d+)\) without time zone\z/) {
    $info->{data_type} = $1;
    $info->{size} = 0 + $2;
    return;
  }

  if ($type eq 'timestamp without time zone') {
    $info->{data_type} = 'timestamp';
    return;
  }

  if ($type eq 'time without time zone') {
    $info->{data_type} = 'time';
    return;
  }

  if ($type =~ /^(interval|timestamp with time zone|time with time zone)\((\d+)\)\z/) {
    $info->{data_type} = $1;
    $info->{size} = 0 + $2;
    return;
  }

  $type =~ s/^character$/char/;
  $type =~ s/^character varying$/varchar/;
  $type =~ s/^bit varying$/varbit/;
  $info->{data_type} = $type;
}

sub _normalize_default_value {
  my ($self, $info, $default, $is_primary_key) = @_;

  return unless defined $default;

  my $value = $default;
  $value =~ s/^\s+//;
  $value =~ s/\s+\z//;

  if ($value =~ /\bnextval\('([^']+)'::(?:text|regclass)\)/i) {
    $info->{is_auto_increment} = 1;
    $info->{sequence} = $1;
    $info->{retrieve_on_insert} = 1 if $is_primary_key;
    return;
  }

  if ($value =~ /^["'](.*?)['"](?:::[\w\s\."]+)?\z/) {
    $info->{default_value} = $1;
  }
  elsif ($value =~ /^\((-?\d.*?)\)(?:::[\w\s\."]+)?\z/) {
    $info->{default_value} = $1;
  }
  elsif ($value =~ /^(-?\d.*?)(?:::[\w\s\."]+)?\z/) {
    $info->{default_value} = $1;
  }
  elsif ($value =~ /^NULL:?/i) {
    my $null = 'null';
    $info->{default_value} = \$null;
  }
  else {
    my $literal = lc($value) eq 'now()' ? 'current_timestamp' : $value;
    $literal =~ s/\bCURRENT_TIMESTAMP\b/lc $&/ge;
    $info->{default_value} = \$literal;
  }

  if (!$info->{is_auto_increment} && $is_primary_key) {
    $info->{retrieve_on_insert} = 1;
  }

  my $type = $info->{data_type} || '';
  if ($type =~ /^bool/i && exists $info->{default_value} && !ref $info->{default_value}) {
    if ($info->{default_value} eq '0') {
      my $false = 'false';
      $info->{default_value} = \$false;
    }
    elsif ($info->{default_value} eq '1') {
      my $true = 'true';
      $info->{default_value} = \$true;
    }
  }
}

sub _normalize_array {
  my ($self, $value) = @_;
  return undef if !defined $value;
  return $value if ref $value eq 'ARRAY';

  my $raw = $value;
  $raw =~ s/^\{|\}$//g;
  return [ grep { length $_ } split /,/, $raw ];
}

1;
