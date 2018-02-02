use 5.20.0;
use warnings;
package Ix::DBIC::AccountResult;

use parent 'DBIx::Class';

use experimental qw(signatures postderef);

sub account_rs ($self, $rs_name) {
  my $rs = $self->result_source->schema->resultset($rs_name)->search({
    'me.accountId' => $self->accountId,
  });

  if ($rs->result_class->isa('Ix::DBIC::Result')) {
    $rs = $rs->search({ 'me.isActive' => 1 });
  }

  return $rs;
}

sub account_rs_including_inactive ($self, $rs_name) {
  return $self->result_source->schema->resultset($rs_name)->search({
    'me.accountId' => $self->accountId,
  });
}

1;
