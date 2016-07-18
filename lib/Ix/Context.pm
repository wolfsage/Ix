use 5.20.0;
package Ix::Context;

use Moose::Role;
use experimental qw(signatures postderef);

use Ix::Error;
use Ix::Result;

use namespace::autoclean;

requires 'datasetId';
requires 'is_system';

has schema => (
  is   => 'ro',
  required => 1,
);

has processor => (
  is   => 'ro',
  does => 'Ix::Processor',
  required => 1,
);

has state => (
  is => 'ro',
  lazy => 1,
  default => sub ($self) {
    require Ix::AccountState;
    Ix::AccountState->new({ context => $self });
  },
);

has created_ids => (
  is => 'ro',
  reader   => '_created_ids',
  init_arg => undef,
  default  => sub {  {}  },
);

sub log_created_id ($self, $type, $creation_id, $id) {
  $self->_created_ids->{$type}{$creation_id} = $id;
}

sub get_created_id ($self, $type, $creation_id) {
  return $self->_created_ids->{$type}{$creation_id};
}

sub process_request ($self, $calls) {
  $self->processor->process_request($self, $calls);
}

sub error ($ctx, $type, $prop = {}, $ident = undef, $payload = undef) {
  Ix::Error::Generic->new({
    error_type => $type,
    properties => $prop,
    ($ident
      ? (_exception_report => Ix::ExceptionReport->new({
          ident => $ident,
          ($payload ? (payload => $payload) : ()),
        }))
      : ()),
  });
}

sub internal_error ($ctx, $ident, $payload = undef) {
  Ix::Error::Internal->new({
    _exception_report => Ix::ExceptionReport->new({
      ident => $ident,
      ($payload ? (payload => $payload) : ()),
    }),
  });
}

sub result ($ctx, $type, $prop = {}) {
  Ix::Result::Generic->new({
    result_type       => $type,
    result_properties => $prop,
  });
}

1;
