use 5.20.0;
package Ix::Context;

use Moose;
use experimental qw(signatures postderef);

use namespace::autoclean;

has accountId => (
  is => 'ro',
  required => 1,
);

has schema => (
  is => 'ro',
  required => 1,
);

__PACKAGE__->meta->make_immutable;
1;
