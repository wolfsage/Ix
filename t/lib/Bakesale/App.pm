use 5.20.0;
package Bakesale::App;
use Moose;
use experimental qw(signatures postderef);

use Bakesale;

with 'Ix::App';

use JSON;

use namespace::autoclean;

has '+processor' => (default => sub {
  Bakesale->new({ schema => Bakesale::Test->test_schema() }),
});

1;
