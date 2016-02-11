use 5.20.0;
package Ix::Error;
use Moose::Role;
use experimental qw(signatures postderef);

with 'Throwable', 'StackTrace::Auto';

use namespace::autoclean;

sub result_type { 'error' }

requires 'result_properties';

requires 'error_type';

package Ix::Error::Generic {
  use Moose;
  with 'Ix::Error';

  use namespace::autoclean;

  sub result_properties {
    return { type => $result->type };
  }

  has error_type => (
    is  => 'ro',
    isa => 'Str', # TODO specify -- rjbs, 2016-02-11
    required => 1,
  );

  __PACKAGE__->meta->make_immutable;
}

1;
