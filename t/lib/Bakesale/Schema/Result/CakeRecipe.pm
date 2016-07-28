package Bakesale::Schema::Result::CakeRecipe;
use base qw/DBIx::Class::Core/;

__PACKAGE__->load_components(qw/+Ix::DBIC::Result/);

__PACKAGE__->table('cake_recipes');

__PACKAGE__->ix_add_columns;

__PACKAGE__->ix_add_properties(
  type         => { data_type => 'text',    is_user_mutable => 1 },
  avg_review   => { data_type => 'integer', is_user_mutable => 1 },
  is_delicious => { data_type => 'boolean', is_user_mutable => 1 },
);

__PACKAGE__->set_primary_key('id');

sub ix_type_key { 'cakeRecipes' }

sub ix_default_properties {
  return {
    is_delicious => 1,
  };
}

1;
