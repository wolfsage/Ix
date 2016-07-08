use 5.20.0;
package Ix::Context;

use Moose::Role;
use experimental qw(signatures postderef);

use namespace::autoclean;

requires 'accountId';
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

1;
