use 5.20.0;
use warnings;
package Ix::DBIC::Schema;

use parent 'DBIx::Class';

use experimental qw(signatures postderef);

sub ix_finalize ($self) {
	my $source_reg = $self->source_registrations;
  for my $moniker (keys %$source_reg) {
    my $rclass = $source_reg->{$moniker}->result_class;
    $rclass->ix_finalize if $rclass->can('ix_finalize');
  }
}

1;
