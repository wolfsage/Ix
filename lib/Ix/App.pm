use 5.20.0;
package Ix::App;

use Moose::Role;
use experimental qw(signatures postderef);

use Data::GUID qw(guid_string);
use JSON;
use Plack::Request;
use Try::Tiny;
use Safe::Isa;

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

has log_all_transactions => (
  is  => 'ro',
  isa => 'Bool',
  default => 0,
);

sub log_transaction {}

has psgi_app => (
  is  => 'ro',
  isa => 'CodeRef',
  lazy => 1,
  builder => '_build_psgi_app',
);

sub to_app ($self) { $self->psgi_app }

sub _build_psgi_app ($self) {
  return sub ($env) {
    my $req = Plack::Request->new($env);

    if ($req->method eq 'OPTIONS') {
      return [
        200,
        [
          'Access-Control-Allow-Origin' => '*',
          'Access-Control-Allow-Methods' => 'POST,GET,OPTIONS',
          'Access-Control-Allow-Headers' => 'Accept,Authorization,Content-Type,X-ME-ClientVersion,X-ME-LastActivity',
          'Access-Control-Max-Age' => 86400,
        ],
        [ '' ],
      ];
    }

    state $transaction_number;
    $transaction_number++;
    $req->env->{'ix.transaction'} = {
      guid => guid_string(),
      time => Ix::DateTime->now,
      seq  => $transaction_number,
      content_type => $req->content_type,
    };

    if ($req->content_type =~ m{^(text/|application/json)}n) {
      $req->env->{'ix.transaction'}{body} = $req->raw_body;
    }

    my $ctx;

    my $res = try {
      $self->_core_request(\$ctx, $req);
    } catch {
      my $error = $_;

      # Let HTTP::Throwable pass through
      if ($error->$_can('as_psgi')) {
        return $error->as_psgi;
      }

      my $guid = $ctx ? $ctx->report_exception($error) : '';

      return [
        500,
        [
          'Content-Type', 'application/json',
          'Access-Control-Allow-Origin' => '*', # ?
          ($guid ? ('Ix-Request-GUID' => $guid) : ()),
        ],
        [ qq<{"error":"internal","guid":"$guid"}> ],
      ];
    };

    my @error_guids = $ctx ? $ctx->logged_exception_guids : ();

    if (@error_guids or $self->log_all_transactions) {
      # We delete this so that when we stick the request into it, we don't
      # create a reference cycle.
      my $to_log = delete $req->env->{'ix.transaction'};

      $to_log->{exceptions} = \@error_guids;
      $to_log->{request} = $req;
      $to_log->{response} = $res; # XXX use Plack::Response? -- rjbs, 2016-08-16

      $self->log_transaction($to_log);
    }

    for (@error_guids) {
      $env->{'psgi.errors'}->print("exception was reported: $_\n")
    }

    return $res;
  }
}

sub _core_request ($self, $ctx_ref, $req) {
  $$ctx_ref = $self->processor->context_from_plack_request($req);

  my $calls = try { $self->decode_json( $req->raw_body ); };
  unless ($calls) {
    return [
      400,
      [
        'Content-Type', 'application/json',
        'Access-Control-Allow-Origin' => '*',
      ],
      [ '{"error":"could not decode request"}' ],
    ];
  }

  $req->env->{'ix.transaction'}{jmap}{calls} = $calls;
  my $result  = $$ctx_ref->process_request( $calls );
  my $json    = $self->encode_json($result);

  return [
    200,
    [
      'Content-Type', 'application/json',
      'Access-Control-Allow-Origin' => '*',
      'Ix-Exchange-GUID' => $req->env->{'ix.transaction'}{guid},
    ],
    [ $json ],
  ];
}

1;
