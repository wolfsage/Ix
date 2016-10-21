use 5.20.0;
package Ix::Context::WithAccount;

use Moose::Role;
use experimental qw(signatures postderef);

use Ix::Error;
use Ix::Result;

use namespace::autoclean;

requires 'account_type';
requires 'accountId';

has root_context => (
  is     => 'ro',
  does   => 'Ix::Context',
  required => 1,
  handles  => [ qw(
    schema
    processor

    get_created_id log_created_id

    log_exception_guid
    report_exception

    record_call_info
    _save_states

    error
    internal_error
    result
  ) ],
);

sub state ($self) {
  $self->root_context->state_for_account(
    $self->account_type,
    $self->accountId,
  );
}

sub with_account ($self, $account_type, $accountId) {
  if (
    $account_type eq $self->account_type
    &&
    ($accountId // $self->accountId) eq $self->accountId
  ) {
    return $self;
  }

  $self->internal_error("conflicting recontextualization")->throw;
}

1;
