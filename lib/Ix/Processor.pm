use 5.20.0;
package Ix::Processor;
use Moose::Role;
use experimental qw(signatures postderef);

use Safe::Isa;
use Try::Tiny;

use namespace::autoclean;

requires 'handler_for';

sub process_request ($self, $calls) {
  my @results;

  # I believe this will end up used as a sideband to communicate things like
  # objects created for temporary ids.  -- rjbs, 2016-02-11
  my %ephemera;

  CALL: for my $call (@$calls) {
    # On one hand, I am tempted to disallow ambiguous cids here.  On the other
    # hand, the spec does not. -- rjbs, 2016-02-11
    my ($method, $arg, $cid) = @$call;

    my $handler = $self->handler_for( $method, \%ephemera );

    unless ($handler) {
      push @results, [ error => { type => 'unknownMethod' }, $cid ];
      next CALL;
    }

    my @rv = try {
      $self->$handler($arg);
    } catch {
      if ($_->$_DOES('Ix::Error')) {
        return $_;
      } else {
        die $_;
      }
    };

    push @results, [
      $_->result_type,
      $_->result_attributes,
      $cid,
    ];
  }

  return \@results;
}

1;
