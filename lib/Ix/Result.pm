use 5.20.0;
package Ix::Result;
use Moose::Role;
use experimental qw(signatures postderef);

use namespace::autoclean;

requires 'result_type';
requires 'result_properties';

package Ix::Result::Generic {
  use Moose;
  use experimental qw(signatures postderef);

  use namespace::autoclean;

  has result_type => (is => 'ro', isa => 'Str', required => 1);
  has result_properties => (
    is  => 'ro',
    isa => 'HashRef',
    required => 1,
  );

  with 'Ix::Result';
};

1;
