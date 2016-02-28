use 5.20.0;
package Bakesale::App;
use Moose;
use experimental qw(signatures postderef);

use Bakesale;

with 'Ix::App';

use JSON;

use namespace::autoclean;

has connect_info => (
  lazy    => 1,
  default => sub {
    my $info = Bakesale::Test->test_schema_connect_info;
  },
);

has '+processor' => (default => sub { Bakesale->new });

1;
