package Bakesale::Schema::Result::Cookie;
use base qw/DBIx::Class::Core/;

__PACKAGE__->load_components(qw/+Ix::DBIC::Result/);

__PACKAGE__->table('cookies');

__PACKAGE__->ix_add_columns;

__PACKAGE__->ix_add_properties(
  type       => { data_type => 'text', },
  baked_at   => { data_type => 'datetime', is_optional => 1 },
  expires_at => { data_type => 'datetime', is_optional => 0 },
  delicious  => { data_type => 'string', is_optional => 0 },
);

__PACKAGE__->set_primary_key('id');

sub ix_type_key { 'cookies' }

sub ix_default_properties {
  return {
    baked_at => Ix::DateTime->now,
    expires_at => Ix::DateTime->now->add(days => 3),
    delicious => 'yes',
  };
}

1;
