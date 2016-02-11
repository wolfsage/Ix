use 5.20.0;
package Ix::Exception;
use Moose::Role;
use experimental qw(signatures postderef);

with 'Throwable', 'StackTrace::Auto';

use namespace::autoclean;

requires 'default_error_type';

has error_type => (
  is  => 'ro',
  isa => 'Str', # TODO specify -- rjbs, 2016-02-11
  required => 1,
  builder  => 'default_error_type';
);

package Ix::Exception::Generic {
  use Moose;
  with 'Ix::Exception';

  use namespace::autoclean;

  sub default_error_type { ... }

  __PACKAGE__->meta->make_immutable;
}

1;
