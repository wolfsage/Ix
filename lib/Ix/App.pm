use 5.20.0;
package Ix::App;

use Moose::Role;
use experimental qw(signatures postderef);

use Data::GUID qw(guid_string);
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

has processor => (
  is => 'ro',
  required => 1,
);

has _logger => (
  is  => 'ro',
  isa => 'CodeRef',
);

sub to_app ($self) {
  my $logger = $self->_logger;

  return sub ($env) {
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

    my $ctx = $self->processor->get_context({
      # XXX SUPER BOGUS -- rjbs, 2016-05-10
      # accountId => 1,
      userId => 1,
    });

    my $content = $req->raw_body;

    my $request_time = Ix::DateTime->now->iso8601;

    my $guid;
    if ($logger) {
      state $request_number;
      $request_number++;
      $guid = guid_string;
      $logger->( "<<< BEGIN REQUEST $guid\n"
               . "||| TIME: $request_time\n"
               . "||| SEQ : $$ $request_number\n"
               . ($content // "")
               . "\n"
               . ">>> END REQUEST $guid\n");
    }

    my $calls   = $self->decode_json( $content );
    my $result  = $ctx->process_request( $calls );
    my $json    = $self->encode_json($result);

    if ($logger) {
      $logger->( "<<< BEGIN RESPONSE\n"
               . "$json\n"
               . ">>> END RESPONSE\n" );
    }

    return [
      200,
      [
        'Content-Type', 'application/json',
        'Access-Control-Allow-Origin' => '*',
        ($guid ? ('Ix-Request-GUID' => $guid) : ()),
      ],
      [ $json ],
    ];
  }
}

1;
