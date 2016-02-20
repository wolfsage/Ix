use 5.20.0;
use warnings;
package Ix::DBIC::Result;

use parent 'DBIx::Class';

sub ix_type_key { Carp::confess("ix_type_key not implemented") }

# XXX This should probably instead be Rx to validate the user properites.
sub ix_user_property_names { return () };

sub ix_default_properties { return {} }

1;
