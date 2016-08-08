use 5.20.0;
package Ix::Util;

use experimental qw(signatures postderef);

use DateTime::Format::Pg;
use DateTime::Format::RFC3339;
use Sub::Exporter -setup => [ qw(parsedate parsepgdate) ];

my $pg = DateTime::Format::Pg->new();
my $rfc3339 = DateTime::Format::RFC3339->new();

sub parsepgdate ($str) {
  my $dt;
  return unless eval { $dt = $pg->parse_datetime($str) };

  bless $dt, 'Ix::DateTime';
}

sub parsedate ($str) {
  return unless $str =~ /Z\z/; # must be in zulu time
  return if $str =~ /\./; # no fractional seconds

  my $dt;
  return unless eval { $dt = $rfc3339->parse_datetime($str) };

  bless $dt, 'Ix::DateTime';
}

package Ix::DateTime {

  use parent 'DateTime'; # should use DateTime::Moonpig

  use overload '""' => 'as_string';

  sub as_string ($self, @) {
    $rfc3339->format_datetime($self);
  }

  sub TO_JSON ($self) {
    $rfc3339->format_datetime($self);
  }
}

1;
