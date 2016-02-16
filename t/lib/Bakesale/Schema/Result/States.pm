package Bakesale::Schema::Result::States;
use base qw/DBIx::Class::Core/;

__PACKAGE__->table('states');

__PACKAGE__->add_columns(qw( accountid type state ));

__PACKAGE__->set_primary_key(qw( accountid type state ));

1;
