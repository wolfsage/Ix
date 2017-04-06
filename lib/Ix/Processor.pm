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

sub get_database_defaults ($self) {
  my @defaults = ( "SET TIMEZONE TO 'UTC'" );

  if ($self->can('database_defaults')) {
    push @defaults, $self->database_defaults;
  }

  return \@defaults;
}

sub schema_connection ($self) {
  $self->schema_class->connect(
    $self->connect_info,
    {
      on_connect_do  => $self->get_database_defaults,
      auto_savepoint => 1,
      quote_names    => 1,
    },
  );
}

1;
