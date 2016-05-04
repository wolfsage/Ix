package Bakesale::Schema::Result::Cake;
use base qw/DBIx::Class::Core/;

__PACKAGE__->load_components(qw/+Ix::DBIC::Result/); # for example

__PACKAGE__->table('cakes');

__PACKAGE__->ix_add_columns;

__PACKAGE__->add_columns(
  type        => { is_nullable => 0 },
  layer_count => { data_type => 'integer',  is_nullable => 0 },
  baked_at    => { data_type => 'datetime', is_nullable => 0 },
  recipeId    => { data_type => 'integer' },
);

__PACKAGE__->set_primary_key('id');

sub ix_type_key { 'cakes' }

sub ix_user_property_names { qw(type layer_count recipeId) }

sub ix_default_properties {
  return { baked_at => Ix::DateTime->now };
}

__PACKAGE__->belongs_to(
  recipe => 'Bakesale::Schema::Result::CakeRecipe',
  { 'foreign.id' => 'self.recipeId' },
);

1;
