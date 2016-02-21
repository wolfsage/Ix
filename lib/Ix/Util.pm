use 5.20.0;
package Ix::Util;

use experimental qw(signatures postderef);

use DateTime::Format::RFC3339;
use Ix::Error;
use Ix::Result;
use Sub::Exporter -setup => [ qw(error result parsedate) ];

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

my $rfc3339 = DateTime::Format::RFC3339->new();

sub parsedate ($str) {
  return unless $str =~ /Z\z/; # must be in zulu time
  return if $str =~ /\./; # no fractional seconds

  my $dt;
  return unless eval { $dt = $rfc3339->parse_datetime($str) };

  bless $dt, 'Ix::DateTime';
}

package Ix::DateTime {

  use parent 'DateTime'; # should use DateTime::Moonpig

  sub as_string ($self) {
    $rfc3339->format_datetime($self);
  }

  sub TO_JSON ($self) {
    $rfc3339->format_datetime($self);
  }
}

1;
