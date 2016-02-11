use 5.20.0;
package Ix::Util;
use experimental qw(signatures postderef);

use Ix::Error;
use Sub::Exporter -setup => [ qw(error) ];

sub error ($type) {
  Ix::Error::Generic->new({
    error_type => $type,
  });
}

1;
