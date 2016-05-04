package Bakesale::Schema::Result::State;
use base qw/DBIx::Class::Core/;

__PACKAGE__->load_components(qw/+Ix::DBIC::StatesResult/);

__PACKAGE__->table('states');

__PACKAGE__->ix_setup_states_result;

1;
