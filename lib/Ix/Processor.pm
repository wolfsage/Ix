use 5.20.0;
package Ix::Processor;
use Moose::Role;
use experimental qw(signatures postderef);

use Safe::Isa;
use Try::Tiny;

use namespace::autoclean;

requires 'handler_for';

# It is tempting to wrap this in a transaction.  Consider the case where a
# method does not return an Ix::Result, so we can't map it into the final
# result set.  That's going to throw an exception, now.  We could catch it and
# report "garbledResponse" as an error, so that the rest of the methods may
# execute, but it indicates a fundamental brokenness of the underlying system,
# and perhaps the entire request should be discarded.  If we do that without a
# response, though, the client is not knowing about changes that have been
# affected.  With an all-encompassing transaction in play, though, the client
# can be given a single "itBroke" error, with all changes rolled back.
#
# This may be needed anyway, since entire requests are executed with
# transactional isolation! -- rjbs, 2016-02-11

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

    RV: for my $i (0 .. $#rv) {
      push @results, $_->$_DOES('Ix::Result')
                   ? [ $_->result_type, $_->result_attribute, $cid ]
                   : [ error => 'garbledResponse', $cid ];

      if ($results[-1] eq 'error' && $i < $#rv) {
        # In this branch, we have a potential return value like:
        # (
        #   [ valid => ... ],
        #   [ error => ... ],
        #   [ valid => ... ],
        # );
        #
        # According to the JMAP specification ("§ Errors"), we shouldn't be
        # getting anything after the error.  So, remove it, but also file an
        # exception report. -- rjbs, 2016-02-11
        #
        # TODO: file internal error report -- rjbs, 2016-02-11
        last RV;
      }
    }
  }

  return \@results;
}

1;
