package Bakesale::Schema::Result::CakeRecipe;
use base qw/DBIx::Class::Core/;

__PACKAGE__->load_components(qw/+Ix::DBIC::Result/); # for example

__PACKAGE__->table('cake_recipes');

__PACKAGE__->ix_add_columns;

__PACKAGE__->add_columns(
  type        => { is_nullable => 0 },
  avg_review  => { data_type => 'integer', is_nullable => 0 },
);

__PACKAGE__->set_primary_key('id');

sub ix_type_key { 'cakeRecipe' }

sub ix_user_property_names { qw(avg_review) }

sub ix_default_properties {
  return { baked_at => Ix::DateTime->now };
}

1;
