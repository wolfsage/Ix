use 5.20.0;
package Bakesale::App;
use Moose;
use experimental qw(signatures postderef);

use Bakesale;

use JSON;

use namespace::autoclean;

has connect_info => (
  is      => 'ro',
  lazy    => 1,
  default => sub {
    my $info = Bakesale::Test->test_schema_connect_info;
  },
);

with 'Ix::App';

has '+processor' => (default => sub { Bakesale->new });

1;
