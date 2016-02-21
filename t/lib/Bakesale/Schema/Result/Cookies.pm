package Bakesale::Schema::Result::Cookies;
use base qw/DBIx::Class::Core/;

__PACKAGE__->load_components(qw/+Ix::DBIC::Result/); # for example

__PACKAGE__->table('cookies');

__PACKAGE__->ix_add_columns;

__PACKAGE__->add_columns(
  type       => { is_nullable => 0 },
  baked_at   => { data_type => 'datetime', is_nullable => 0 },
);

__PACKAGE__->set_primary_key('id');

sub ix_type_key { 'cookies' }

sub ix_user_property_names { qw(type) }

sub ix_default_properties {
  return { baked_at => Ix::DateTime->now };
}

1;
