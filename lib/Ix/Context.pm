use 5.20.0;
package Ix::Context;

use Moose::Role;
use experimental qw(signatures postderef);

use Ix::Error;
use Ix::Result;

use namespace::autoclean;

requires 'with_dataset'; # $dctx = $ctx->with_dataset(type => optional_id)
requires 'is_system';

sub root_context ($self) { $self }

has schema => (
  is   => 'ro',
  required => 1,
);

has processor => (
  is   => 'ro',
  does => 'Ix::Processor',
  required => 1,
);

has _state_for => (
  is      => 'ro',
  default => sub {  {}  },
);

sub state_for_dataset ($self, $dataset_type, $dataset_id) {
  my $states = $self->_state_for;

  require Ix::DatasetState;
  return $states->{ $dataset_type }{ $dataset_id } ||= Ix::DatasetState->new({
    context => $self,
    dataset_type => $dataset_type,
    datasetId    => $dataset_id,
  });
}

sub _save_states ($self) {
  $_->_save_states for map {; values %$_ } values $self->_state_for->%*;
  return;
}

has created_ids => (
  is => 'ro',
  reader   => '_created_ids',
  init_arg => undef,
  default  => sub {  {}  },
);

has call_info => (
  is => 'ro',
  traits   => [ 'Array' ],
  handles  => {
    _add_call_info => 'push',
  },

  default => sub { [] },
);

sub record_call_info ($self, $call, $info) {
  $self->_add_call_info([ $call, $info ]);
}

sub log_created_id ($self, $type, $creation_id, $id) {
  my $reg = ($self->_created_ids->{$type} //= {});

  if ($reg->{$creation_id}) {
    $reg->{$creation_id} = \undef;
  } else {
    $reg->{$creation_id} = $id;
  }

  return;
}

sub get_created_id ($self, $type, $creation_id) {
  my $id = $self->_created_ids->{$type}{$creation_id};

  $self->error(duplicateCreationId => {})->throw
    if ref $id && ! defined $$id;

  return $id;
}

sub process_request ($self, $calls) {
  $self->processor->process_request($self, $calls);
}

has logged_exception_guids => (
  init_arg => undef,
  lazy     => 1,
  default  => sub {  []  },
  traits   => [ 'Array' ],
  handles  => {
    logged_exception_guids => 'elements',
    log_exception_guid     => 'push',
  },
);

sub report_exception ($ctx, $exception) {
  my $guid = $ctx->processor->file_exception_report($ctx, $exception);
  $ctx->log_exception_guid($guid);
  return $guid;
}

sub error ($ctx, $type, $prop = {}, $ident = undef, $payload = undef) {
  my $report_guid;
  if (defined $ident) {
    my $report = Ix::ExceptionWrapper->new({
      ident => $ident,
      ($payload ? (payload => $payload) : ()),
    });

    $report_guid = $ctx->report_exception($report);
  }

  Ix::Error::Generic->new({
    error_type => $type,
    properties => $prop,
    ($report_guid ? (report_guid => $report_guid) : ()),
  });
}

sub internal_error ($ctx, $ident, $payload = undef) {
  my $report = Ix::ExceptionWrapper->new({
    ident => $ident,
    ($payload ? (payload => $payload) : ()),
  });

  my $report_guid = $ctx->report_exception($report);

  Ix::Error::Internal->new({
    error_ident => $ident,
    report_guid => $report_guid,
  });
}

sub result ($ctx, $type, $prop = {}) {
  Ix::Result::Generic->new({
    result_type       => $type,
    result_arguments => $prop,
  });
}

1;
