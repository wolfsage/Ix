use 5.20.0;
package Ix::App::JMAP;

use Moose::Role;
use experimental qw(signatures postderef);

use Try::Tiny;

use namespace::autoclean;

with 'Ix::App';

sub _core_request ($self, $ctx, $req) {
  my $calls = try { $self->decode_json( $req->raw_body ); };
  unless ($calls) {
    return [
      400,
      [
        'Content-Type', 'application/json; charset=utf-8',
      ],
      [ '{"error":"could not decode request"}' ],
    ];
  }

  $req->env->{'ix.transaction'}{jmap}{calls} = $calls;
  my $result  = $ctx->handle_calls($calls, { no_implicit_client_ids => 1 });
  my $json    = $self->encode_json($result->as_struct);

  return [
    200,
    [
      'Content-Type', 'application/json; charset=utf-8',
    ],
    [ $json ],
  ];
}

1;
