use 5.20.0;
package Ix::App;

use Moose::Role;
use experimental qw(signatures postderef);

use JSON;
use Plack::Request;

use namespace::autoclean;

has json_codec => (
  is => 'ro',
  default => sub { JSON->new->utf8->canonical },
  handles => {
    encode_json => 'encode',
    decode_json => 'decode',
  },
);

has processor => (
  is => 'ro',
  required => 1,
  handles  => [ qw(process_request) ],
);

sub app ($self) {
  return sub ($env) {
    my $req = Plack::Request->new($env);
    my $content = $req->raw_body;
    my $calls   = $self->decode_json( $content );
    my $result  = $self->process_request( $calls );

    return [
      200,
      [ 'Content-Type', 'application/json' ],
      [ $self->encode_json($result) ],
    ];
  }
}

1;
