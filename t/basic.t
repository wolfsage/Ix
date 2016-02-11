use 5.20.0;
use warnings;
use experimental qw(signatures postderef);

package Bakesale::PieTypes {
  use Moose;
  with 'Ix::Result';

  use experimental qw(signatures postderef);

  has flavors => (is => 'ro');

  sub result_type { 'pieTypes' }

  sub result_properties ($self) {
    return {
      flavors => [ $self->flavors->@* ],
    };
  }

  __PACKAGE__->meta->make_immutable;
  1;
}

package Bakesale {
  use Moose;
  with 'Ix::Processor';

  use experimental qw(signatures postderef);

  use Ix::Util qw(error);

  use namespace::autoclean;

  sub handler_for ($self, $method) {
    return 'pie_type_list' if $method eq 'pieTypes';
    return;
  }

  sub pie_type_list ($self, $arg = {}, $ephemera = {}) {
    my $only_tasty = delete local $arg->{tasty};
    return error('invalidArguments') if keys %$arg;

    my @flavors = qw(pumpkin apple pecan);
    push @flavors, qw(cherry eel) unless $only_tasty;

    return Bakesale::PieTypes->new({ flavors => \@flavors });
  }

  __PACKAGE__->meta->make_immutable;
  1;
}

use Test::More;

my $res = Bakesale->process_request([
  [ pieTypes => { tasty => 1 }, 'a' ],
  [ pieTypes => { tasty => 0 }, 'b' ],
]);

is_deeply(
  $res,
  [
    [ pieTypes => { flavors => [ qw(pumpkin apple pecan) ] }, 'a' ],
    [ pieTypes => { flavors => [ qw(pumpkin apple pecan cherry eel) ] }, 'b' ],
  ],
  "the most basic possible call works",
) or diag explain($res);

done_testing;
