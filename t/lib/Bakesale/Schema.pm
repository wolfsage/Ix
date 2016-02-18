use 5.20.0;
use warnings;
package Bakesale::Schema;
use base qw/DBIx::Class::Schema/;

__PACKAGE__->load_namespaces(
  default_resultset_class => '+Ix::DBIC::ResultSet',
);

1;
