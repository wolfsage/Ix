use 5.20.0;
package Ix::Context::Error;

use Moose::Role;
use experimental qw(signatures postderef);

use namespace::autoclean;

use Plack::Response;

requires 'code';

sub to_psgi_response ($self) {
  my $resp = Plack::Response->new(
    $self->code,
    [
      'Content-Type', 'application/json',
      'Access-Control-Allow-Origin' => '*',
    ],
  );

  $self->modify_response($resp);

  return $resp->finalize;
}

sub modify_response { }

1;
