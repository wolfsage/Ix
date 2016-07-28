use strict;
use warnings;
use experimental qw(postderef signatures);
package Bakesale::Schema::Result::User;
use base qw/DBIx::Class::Core/;

__PACKAGE__->load_components(qw/+Ix::DBIC::Result/);

__PACKAGE__->table('users');

__PACKAGE__->ix_add_columns;

__PACKAGE__->ix_add_properties(
  username    => { data_type => 'text', is_user_mutable => 1 },
);

__PACKAGE__->set_primary_key('id');

sub ix_type_key { 'users' }

1;
