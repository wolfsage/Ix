use 5.20.0;
use warnings;
package Ix::StateComparison;

use experimental qw(signatures postderef);

sub in_sync ($class) { bless \do { my $x = 1 }, $class }
sub bogus   ($class) { bless \do { my $x = 2 }, $class }
sub resync  ($class) { bless \do { my $x = 3 }, $class }
sub okay    ($class) { bless \do { my $x = 4 }, $class }

sub is_in_sync ($self) { return $$self == 1 }
sub is_bogus   ($self) { return $$self == 2 }
sub is_resync  ($self) { return $$self == 3 }
sub is_okay    ($self) { return $$self == 4 }

1;
