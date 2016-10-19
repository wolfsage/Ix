use 5.20.0;
package Ix::Context::WithDataset;

use Moose::Role;
use experimental qw(signatures postderef);

use Ix::Error;
use Ix::Result;

use namespace::autoclean;

requires 'dataset_type';
requires 'datasetId';

has root_context => (
  is     => 'ro',
  does   => 'Ix::Context',
  weak_ref => 1,
  required => 1,
  handles  => [ qw(
    schema
    processor

    get_created_id log_created_id

    log_exception_guid
    report_exception

    error
    internal_error
    result
  ) ],
);

sub state ($self) {
  $self->root_context->state_for_dataset(
    $self->dataset_type,
    $self->datasetId,
  );
}

sub with_dataset ($self, $dataset_type, $datasetId) {
  if (
    $dataset_type eq $self->dataset_type
    &&
    ($datasetId // $self->datasetId) eq $self->datasetId
  ) {
    return $self;
  }

  $self->internal_error("conflicting recontextualization")->throw;
}

1;
