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
        'Content-Type', 'application/json',
      ],
      [ '{"error":"could not decode request"}' ],
    ];
  }

  $req->env->{'ix.transaction'}{jmap}{calls} = $calls;
  my $result  = $ctx->process_request( $calls );
  my $json    = $self->encode_json($result);

  return [
    200,
    [
      'Content-Type', 'application/json',
    ],
    [ $json ],
  ];
}

1;
