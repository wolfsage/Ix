package Bakesale::Schema::Result::Cookies;
use base qw/DBIx::Class::Core/;

__PACKAGE__->load_components(qw/InflateColumn::DateTime/); # for example
__PACKAGE__->table('cookies');

__PACKAGE__->add_columns(qw/ id accountid state type baked_at /);

1;
