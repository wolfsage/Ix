use 5.20.0;
package Bakesale::App;
use Moose;
use experimental qw(signatures postderef);

use Bakesale;

use JSON;

use namespace::autoclean;

with 'Ix::App';

has '+processor' => (default => sub { Bakesale->new });

around _core_request => sub ($orig, $self, $ctx_ref, $req) {
  if ($req->path_info eq '/secret') {
    return [
      200,
      [ "Content-Type" => 'text/plain' ],
      [ "Your secret is safe with me.\n" ],
    ];
  }

  return $self->$orig($ctx_ref, $req);
};

1;
