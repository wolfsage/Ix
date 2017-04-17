use strict;
use warnings;
package Exception::Reporter::Summarizer::Ix;

use parent 'Exception::Reporter::Summarizer';

=head1 OVERVIEW

If added as a summarizer to an L<Exception::Reporter>, this plugin will
summarize L<Ix> exception wrappers. This should be the first
summarizer to be checked so that it can generate a proper error message,
otherwise your error reports may simply say C<Ix::ExceptionWrapper=HASH...>.

=cut

use Try::Tiny;

sub new {
  my ($class, $arg) = @_;
  $arg ||= {};

  return bless { } => $class;
}

sub can_summarize {
  my ($self, $entry) = @_;
  return try {
    $entry->[1]->isa('Ix::ExceptionWrapper');
  };
}

sub summarize {
  my ($self, $entry) = @_;
  my ($name, $err, $arg) = @$entry;

  my @summaries;

  push @summaries, $self->summarize_error($err);
  push @summaries, $self->summarize_stack_trace($err);

  return @summaries;
}

sub summarize_error {
  my ($self, $err) = @_;

  my %to_dump = (
    ident => $err->ident,
    payload => $err->payload,
  );

  return {
    filename => 'error_string.txt',
    %{ $self->dump(\%to_dump, { basename =>'error' }) },
    ident => $err->ident,
  };
}

sub summarize_stack_trace {
  my ($self, $err) = @_;

  return {
    filename => 'stack_trace.txt',
    %{ $self->dump($err->stack_trace->as_string, { basename => 'stack_trace' }) },
    ident => 'stack_trace'
  };
}

1;
