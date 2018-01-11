use v5.24.0;
package Ix::JMAP::SentenceBroker;

use Moose;

with 'JMAP::Tester::Role::SentenceBroker';

use experimental 'signatures';

use JMAP::Tester::Response::Sentence;
use JMAP::Tester::Response::Paragraph;
use JSON::Typist;

sub client_ids_for_items ($self, $items) {
  map {; $_->[1] } @$items
}

sub sentence_for_item ($self, $item) {
  JMAP::Tester::Response::Sentence->new({
    name      => $item->[0]->result_type,
    arguments => $item->[0]->result_arguments,
    client_id => $item->[1],

    sentence_broker => $self,
  });
}

sub paragraph_for_items {
  my ($self, $items) = @_;

  return JMAP::Tester::Response::Paragraph->new({
    sentences => [
      map {; $self->sentence_for_item($_) } @$items
    ],
  });
}

sub abort_callback       { sub { ... } };

sub strip_json_types {
  state $typist = JSON::Typist->new;
  $typist->strip_types($_[1]);
}

no Moose;

1;
