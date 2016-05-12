use 5.20.0;
package Bakesale::App;
use Moose;
use experimental qw(signatures postderef);

use Bakesale;

use JSON;

use namespace::autoclean;

with 'Ix::App';

has '+processor' => (default => sub { Bakesale->new });

1;
