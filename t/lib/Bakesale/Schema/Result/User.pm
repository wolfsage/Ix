use strict;
use warnings;
use experimental qw(postderef signatures);
package Bakesale::Schema::Result::User;
use base qw/DBIx::Class::Core/;

__PACKAGE__->load_components(qw/+Ix::DBIC::Result/); # for example

__PACKAGE__->table('users');

__PACKAGE__->ix_add_columns;

__PACKAGE__->add_columns(
  username    => { data_type => 'text' },
);

__PACKAGE__->set_primary_key('id');

sub ix_type_key { 'users' }

sub ix_user_property_names { qw(username) }

1;
