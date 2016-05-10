package Bakesale::Context;
use Moose;

use experimental qw(lexical_subs signatures postderef);

has userId => (
  is       => 'ro',
  required => 1,
);

has user => (
  isa      => 'Object',
  reader   => 'user',
  writer   => '_set_user',
  init_arg => undef,
  lazy     => 1,
  handles  => [ qw(accountId) ],
  clearer  => '_clear_user', # trigger this after setUsers, surely?
  default  => sub ($self) {
    return $self->schema->resultset('User')->find($self->userId);
  },
);

with 'Ix::Context';

1;
