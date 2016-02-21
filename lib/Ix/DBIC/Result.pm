use 5.20.0;
use warnings;
package Ix::DBIC::Result;

use parent 'DBIx::Class';

use experimental qw(signatures postderef);

sub ix_type_key { Carp::confess("ix_type_key not implemented") }

# XXX This should probably instead be Rx to validate the user properites.
sub ix_user_property_names { return () };

sub ix_default_properties { return {} }

sub ix_add_columns ($class) {
  $class->add_columns(
    id            => { data_type => 'integer', is_auto_increment => 1 },
    accountId     => { is_nullable => 0 },
    modSeqCreated => { data_type => 'integer' },
    modSeqChanged => { data_type => 'integer' },
    dateDeleted   => { data_type => 'datetime', is_nullable => 1 },
  );
}

1;
