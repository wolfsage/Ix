use 5.20.0;
use warnings;
use experimental qw(lexical_subs signatures postderef refaliasing);

use lib 't/lib';
use Test::More;

eval <<'EOF';
  package Thing;
  use base qw/DBIx::Class::Core/;

  __PACKAGE__->load_components(qw/+Ix::DBIC::Result/);

  __PACKAGE__->table('things');

  __PACKAGE__->ix_add_properties(
    thing       => { },
  );

  1;

EOF

like(
  $@,
  qr/Attempt to add property thing with no data_type/,
  "Cannot create properties with no data_type"
);

done_testing;
