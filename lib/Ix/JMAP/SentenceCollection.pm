use v5.24.0;
package Ix::JMAP::SentenceCollection;

use Moose;

use experimental 'signatures';

with 'JMAP::Tester::Role::SentenceCollection';

use Ix::JMAP::SentenceBroker;
sub sentence_broker {
  state $BROKER = Ix::JMAP::SentenceBroker->new;
}

# [ [ $result, $cid ], ... ]
has result_client_id_pairs => (
  reader  => '_result_client_id_pairs',
  default => sub {  []  },
);

sub results ($self) {
  map {; $_->[0] } $self->_result_client_id_pairs->@*;
}

sub has_errors {
  ($_->[0]->does('Ix::Error') && return 1) for $_[0]->_result_client_id_pairs;
  return;
}

sub result ($self, $n) {
  Carp::confess("there is no result for index $n")
    unless my $pair = $self->_result_client_id_pairs->[$n];
  return $pair->[0];
}

sub items ($self) { $self->_result_client_id_pairs->@* }

sub add_items ($self, $items) {
  push $self->_result_client_id_pairs->@*, @$items;
  return;
}

no Moose;

1;
