use 5.20.0;
package Ix::Error;
use Moose::Role;
use experimental qw(signatures postderef);

with 'Ix::Result', 'Throwable', 'StackTrace::Auto';

use namespace::autoclean;

sub result_type { 'error' }

requires 'error_type';

package Ix::Error::Generic {
  use Moose;

  use experimental qw(signatures postderef);

  use namespace::autoclean;

  sub result_properties ($self) {
    return { type => $self->error_type };
  }

  has error_type => (
    is  => 'ro',
    isa => 'Str', # TODO specify -- rjbs, 2016-02-11
    required => 1,
  );

  with 'Ix::Error';

  __PACKAGE__->meta->make_immutable;
}

1;
