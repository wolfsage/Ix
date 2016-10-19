use 5.20.0;
use warnings;
package Ix::DatasetState;

use Moose;

use experimental qw(signatures postderef);

use namespace::clean;

has context => (
  is => 'ro',
  required => 1,
  weak_ref => 1,
  handles  => [ qw(schema) ],
);

has [ qw(dataset_type datasetId) ] => (
  is  => 'ro',
  isa => 'Str',
  required => 1,
);

has _state_rows => (
  is   => 'ro',
  isa  => 'HashRef',
  lazy => 1,
  init_arg => undef,
  default  => sub ($self) {
    my @rows = $self->schema->resultset('State')->search({
      datasetId => $self->datasetId,
    });

    my %map = map {; $_->type => $_ } @rows;
    return \%map;
  },
);

has _pending_states => (
  is  => 'rw',
  init_arg => undef,
  default  => sub {  {}  },
);

sub _pending_state_for ($self, $type) {
  return $self->_pending_states->{$type};
}

sub state_for ($self, $type) {
  my $pending = $self->_pending_state_for($type);
  return $pending if defined $pending;
  return "0" unless my $row = $self->_state_rows->{$type};
  return $row->highestModSeq;
}

sub lowest_modseq_for ($self, $type) {
  my $row = $self->_state_rows->{$type};
  return $row->lowestModSeq if $row;
  return 0;
}

sub highest_modseq_for ($self, $type) {
  my $row = $self->_state_rows->{$type};
  return $row->highestModSeq if $row;
  return 0;
}

sub ensure_state_bumped ($self, $type) {
  return if defined $self->_pending_state_for($type);
  $self->_pending_states->{$type} = $self->next_state_for($type);
  return;
}

sub next_state_for ($self, $type) {
  my $pending = $self->_pending_state_for($type);
  return $pending if $pending;

  my $row = $self->_state_rows->{$type};
  return $row ? $row->highestModSeq + 1 : 1;
}

sub _save_states ($self) {
  my $rows = $self->_state_rows;
  my $pend = $self->_pending_states;

  for my $type (keys %$pend) {
    if (my $row = $rows->{$type}) {
      $row->update({ highestModSeq => $pend->{$type} });
    } else {
      my $row = $self->schema->resultset('State')->create({
        datasetId => $self->datasetId,
        type      => $type,
        highestModSeq => $pend->{$type},
        lowestModSeq  => 0,
      });

      $rows->{$type} = $row;
    }

    delete $pend->{$type};
  }

  return;
}

1;
