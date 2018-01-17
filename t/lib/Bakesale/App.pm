use 5.20.0;
package Bakesale::App;
use Moose;
use experimental qw(signatures postderef);

use Bakesale;

use JSON::MaybeXS;

use namespace::autoclean;

has transaction_log => (
  init_arg => undef,
  default  => sub {  []  },
  traits   => [ 'Array' ],
  handles  => {
    clear_transaction_log => 'clear',
    logged_transactions   => 'elements',
    emit_transaction_log  => 'push',
  },
);

with 'Ix::App::JMAP';

has '+processor' => (default => sub { Bakesale->new });

sub drain_transaction_log ($self) {
  my @log = $self->logged_transactions;
  $self->clear_transaction_log;
  return @log;
}

around _core_request => sub ($orig, $self, $ctx, $req) {
  if ($req->path_info eq '/secret') {
    return [
      200,
      [ "Content-Type" => 'text/plain' ],
      [ "Your secret is safe with me.\n" ],
    ];
  }

  if ($req->path_info eq '/exception') {
    $ctx->internal_error("I except!")->throw;
  }

  return $self->$orig($ctx, $req);
};

1;
