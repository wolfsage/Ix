use 5.20.0;
package Ix::Util;
use experimental qw(signatures postderef);

use Ix::Error;
use Ix::Result;
use Sub::Exporter -setup => [ qw(error result) ];

sub error ($type, $prop = {}) {
  Ix::Error::Generic->new({
    error_type => $type,
    properties => $prop,
  });
}

sub result ($type, $prop = {}) {
  Ix::Result::Generic->new({
    result_type       => $type,
    result_properties => $prop,
  });
}

1;
