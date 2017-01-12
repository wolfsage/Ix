use 5.20.0;
package Ix::Processor;

use Moose::Role;
use experimental qw(signatures postderef);

use Safe::Isa;
use Try::Tiny;
use Time::HiRes qw(gettimeofday tv_interval);

use namespace::autoclean;

requires 'file_exception_report';

requires 'schema_class';

requires 'connect_info';

requires 'context_from_plack_request';

has behind_proxy => (
  is  => 'rw',
  isa => 'Bool',
  default => 0,
);

sub schema_connection ($self) {
  $self->schema_class->connect(
    $self->connect_info,
    {
      on_connect_do  => "SET TIMEZONE TO 'UTC'",
      auto_savepoint => 1,
      quote_names    => 1,
    },
  );
}

1;
