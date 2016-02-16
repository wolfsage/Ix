package Bakesale::Schema::Result::States;
use base qw/DBIx::Class::Core/;

__PACKAGE__->table('states');

__PACKAGE__->add_columns(qw( account_id type state ));

__PACKAGE__->set_primary_key(qw( account_id type ));

1;
