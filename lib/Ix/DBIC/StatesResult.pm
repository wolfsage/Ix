use 5.20.0;
use warnings;
package Ix::DBIC::StatesResult;

use parent 'DBIx::Class';

use experimental qw(signatures postderef);

sub ix_setup_states_result ($class) {
  $class->add_columns(
    dataset_id     => { data_type => 'integer' },
    type          => { data_type => 'text' },
    lowest_mod_seq  => { data_type => 'integer' },
    highest_mod_seq => { data_type => 'integer' },
  );

  $class->set_primary_key(qw( dataset_id type ));
}

1;
