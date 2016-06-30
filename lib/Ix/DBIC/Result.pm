use 5.20.0;
use warnings;
package Ix::DBIC::Result;

use parent 'DBIx::Class';

use experimental qw(signatures postderef);

use Ix::StateComparison;
use Ix::Validators;

sub ix_type_key { Carp::confess("ix_type_key not implemented") }
sub ix_type_key_singular ($self) {
  $self->ix_type_key =~ s/s\z//r;
}

# XXX This should probably instead be Rx to validate the user properites.
sub ix_user_property_names { return () };

sub ix_default_properties { return {} }

sub ix_add_columns ($class) {
  $class->add_columns(
    id            => {
      data_type         => 'integer',
      ix_data_type      => 'string',
      default_value => \q{pseudo_encrypt(nextval('key_seed_seq')::int)},
      # is_auto_increment => 1
    },
    accountId     => { data_type => 'integer', ix_hidden => 1, },
    modSeqCreated => { data_type => 'integer', ix_hidden => 1, },
    modSeqChanged => { data_type => 'integer', ix_hidden => 1, },
    dateDeleted   => { data_type => 'datetime', is_nullable => 1, ix_hidden => 1 },
  );
}

my %DEFAULT_VALIDATOR = (
  integer => Ix::Validators::integer(),
  string  => Ix::Validators::simplestr(),
);

my %DID_FINALIZE;
sub ix_finalize ($class) {
  if ($DID_FINALIZE{$class}++) {
    Carp::confess("tried to finalize $class a second time");
  }

  my $columns = $class->columns_info;

  for my $name ($class->columns) {
    my $col = $columns->{$name};

    # Skip doing this for hidden columns. -- rjbs, 2016-05-10
    $col->{ix_data_type} //= $col->{data_type};

    $col->{ix_data_type} = 'string'
      if $col->{ix_data_type} eq 'text';

    $col->{ix_validator} //= $DEFAULT_VALIDATOR{ $col->{ix_data_type} };
  }
}

sub ix_get_check     { } # ($self, $ctx, \%arg)
sub ix_create_check  { } # ($self, $ctx, \%rec)
sub ix_update_check  { } # ($self, $ctx, \%rec)
sub ix_destroy_check { } # ($self, $ctx, \%rec)

sub _return_ix_get   { return $_[3]->@* }

sub ix_update_state_string_field { 'modSeqChanged' }

sub ix_state_string ($self, $state) {
  return $state->state_for( $self->ix_type_key ) . "";
}

sub ix_get_extra_search ($self, $ctx) {
  return (
    {},
    {},
  );
}

sub ix_update_extra_search ($self, $ctx, $arg) {
  my $since = $arg->{since};

  return (
    {
      'me.modSeqChanged' => { '>' => $since },
    },
    {},
  );
}

sub ix_update_extra_select {
  return [];
}

sub ix_highest_state ($self, $since, $rows) {
  my $state_string_field = $self->ix_update_state_string_field;
  return $rows->[-1]{$state_string_field};
}

sub ix_update_single_state_conds ($self, $example_row) {
  return { 'me.modSeqChanged' => $example_row->{modSeqChanged} }
}

sub ix_compare_state ($self, $since, $state) {
  my $high_ms = $state->highest_modseq_for($self->ix_type_key);
  my $low_ms  = $state->lowest_modseq_for($self->ix_type_key);

  if ($high_ms  < $since) { return Ix::StateComparison->bogus;   }
  if ($low_ms  >= $since) { return Ix::StateComparison->resync;  }
  if ($high_ms == $since) { return Ix::StateComparison->in_sync; }

  return Ix::StateComparison->okay;
}

1;
