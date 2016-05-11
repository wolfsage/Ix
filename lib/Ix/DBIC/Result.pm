use 5.20.0;
use warnings;
package Ix::DBIC::Result;

use parent 'DBIx::Class';

use experimental qw(signatures postderef);

use Ix::StateComparison;

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
      is_auto_increment => 1
    },
    accountId     => { data_type => 'integer' },
    modSeqCreated => { data_type => 'integer' },
    modSeqChanged => { data_type => 'integer' },
    dateDeleted   => { data_type => 'datetime', is_nullable => 1 },
  );
}

sub ix_finalize ($class) {
  my $columns = $class->columns_info;

  for my $name ($class->columns) {
    # Skip doing this for hidden columns. -- rjbs, 2016-05-10
    $columns->{$name}{ix_data_type} //= $columns->{$name}{data_type};

    $columns->{$name}{ix_data_type} = 'string'
      if $columns->{$name}{ix_data_type} eq 'text';
    warn "ix_data_type for " . $class->ix_type_key . ".$name is $columns->{$name}{ix_data_type}\n";
  }
}

sub ix_create_check  { } # ($self, $ctx, \%rec)
sub ix_update_check  { } # ($self, $ctx, \%rec)
sub ix_destroy_check { } # ($self, $ctx, \%rec)

sub ix_update_state_string_field { 'modSeqChanged' }

sub ix_state_string ($self, $state) {
  return $state->state_for( $self->ix_type_key ) . "";
}

sub ix_update_extra_search ($self, $arg) {
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
