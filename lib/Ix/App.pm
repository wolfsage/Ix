use 5.20.0;
package Ix::App;

use Moose::Role;
use experimental qw(signatures postderef);

use JSON;
use Plack::Request;

use namespace::autoclean;

has json_codec => (
  is => 'ro',
  default => sub {
    JSON->new->utf8->pretty->allow_blessed->convert_blessed->canonical
  },
  handles => {
    encode_json => 'encode',
    decode_json => 'decode',
  },
);

requires 'connect_info';

has processor => (
  is => 'ro',
  required => 1,
);

has _logger => (
  is => 'ro',
  default => sub { sub {} },
);

sub to_app ($self) {
  return sub ($env) {
    state $request_number;
    $request_number++;
    my $request_time = Ix::DateTime->now->iso8601;

    my $req = Plack::Request->new($env);

    if ($req->method eq 'OPTIONS') {
      return [
        200,
        [
          'Access-Control-Allow-Origin' => '*',
          'Access-Control-Allow-Methods' => 'POST,GET,OPTIONS',
          'Access-Control-Allow-Headers' => 'Accept,Authorization,Content-Type,X-ME-ClientVersion,X-ME-LastActivity',
          'Access-Control-Allow-Max-Age' => 60
        ],
        [ '' ],
      ];
    }

    my @connect_info = $self->connect_info->@*;

    my $ctx = $self->processor->get_context({
      accountId => 1,
      connect_info => \@connect_info,
    });

    my $content = $req->raw_body;

    $self->_logger->(
      "$request_time Request $request_number (Request)\n\n"
      . (length($content) ? ($content =~ s/^/  /mgr) : "  (no content)")
      . "\n"
    );

    my $calls   = $self->decode_json( $content );
    my $result  = $ctx->process_request( $calls );
    my $json    = $self->encode_json($result);

    $self->_logger->(
      "$request_time Request $request_number (Response)\n\n"
      . ($json =~ s/^/  /mgr)
      . "\n"
    );

    return [
      200,
      [
        'Content-Type', 'application/json',
        'Access-Control-Allow-Origin' => '*',
      ],
      [ $json ],
    ];
  }
}

1;
