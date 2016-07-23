use 5.20.0;
package Ix::Error;

use Moose::Role;
use experimental qw(signatures postderef);

with 'Ix::Result', 'Throwable';

use namespace::autoclean;

sub result_type { 'error' }

requires 'error_type';

package
  Ix::ExceptionReport {

  use Moose;
  use Data::GUID qw(guid_string);
  use namespace::autoclean;

  with 'StackTrace::Auto';

  has guid => (
    is => 'ro',
    init_arg => undef,
    default  => sub { guid_string() },
  );

  has ident => (
    is => 'ro',
    default => 'unspecified error!',
  );

  has payload => (
    is => 'ro',
    default => sub {  {}  },
  );

  __PACKAGE__->meta->make_immutable;
}

package Ix::Error::Internal {

  use Moose;

  use experimental qw(signatures postderef);

  use namespace::autoclean;

  use overload
    '""' => sub {
      return sprintf "Ix::Error::Internal(%s)\n%s",
        $_[0]->error_type,
        $_[0]->_exception_report->stack_trace->as_string;
    },
    fallback => 1;

  has _exception_report => (
    is => 'ro',
    isa => 'Ix::ExceptionReport',
    required => 1,
  );

  sub error_type { 'internalError' }

  sub result_properties ($self) {
    return { type => 'internalError', guid => $self->_exception_report->guid };
  }

  sub BUILD {
    my ($self) = @_;

    # Obviously this is a placeholder for some future "log to database" or use
    # of Exception::Reporter.  Or both. -- rjbs, 2016-06-01
    my $report = $self->_exception_report;

    warn sprintf "INTERNAL ERROR %s: %s\n%s\n\n%s\n\n%s",
      $report->guid,
      $report->ident,
      $report->stack_trace->as_string,
      ('-' x 78),
      Data::Dumper::Dumper($report->payload);
  }

  with 'Ix::Error';

  __PACKAGE__->meta->make_immutable;
}

package Ix::Error::Generic {

  use Moose;

  use experimental qw(signatures postderef);

  use namespace::autoclean;

  use overload
    '""' => sub {
      my $str = sprintf "Ix::Error::Generic(%s)", $_[0]->error_type;
      $str .= $_[0]->_exception_report->stack_trace->as_string
        if $_[0]->_exception_report;
      return $str;
    },
    fallback => 1;

  sub result_properties ($self) {
    return { $self->properties, type => $self->error_type };
  }

  sub BUILD ($self, @) {
    Carp::confess(q{"type" is forbidden as an error property})
      if $self->has_property('type');

    if (my $report = $self->_exception_report) {
      # Obviously this is a placeholder for some future "log to database" or
      # use of Exception::Reporter.  Or both. -- rjbs, 2016-06-01
      warn sprintf "INTERNAL ERROR %s: %s\n%s\n\n%s\n\n%s",
        $report->guid,
        $report->ident,
        $report->stack_trace->as_string,
        ('-' x 78),
        Data::Dumper::Dumper($self->_exception_report->payload);
    }
  }

  has _exception_report => (
    is  => 'ro',
    isa => 'Ix::ExceptionReport',
  );

  has properties => (
    isa => 'HashRef',
    traits  => [ 'Hash' ],
    handles => { properties => 'elements', has_property => 'exists' },
  );

  has error_type => (
    is  => 'ro',
    isa => 'Str', # TODO specify -- rjbs, 2016-02-11
    required => 1,
  );

  with 'Ix::Error';

  __PACKAGE__->meta->make_immutable;
}

1;
