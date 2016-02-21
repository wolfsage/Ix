use 5.20.0;
use warnings;
package Ix::DBIC::StatesResult;

use parent 'DBIx::Class';

use experimental qw(signatures postderef);

sub ix_setup_states_result ($class) {
  $class->add_columns(
    accountId   => { is_nullable => 0 },
    type        => { data_type => 'text' },
    state       => { data_type => 'integer', is_nullable => 0 },
  );

  $class->set_primary_key(qw( accountId type ));
}

1;
