use 5.20.0;

package Bakesale::Context {
  use warnings;
  use experimental qw(signatures postderef);

  sub account_id ($self) { 1 }

  our $Context = bless { } => __PACKAGE__;
}

package Bakesale::Test {
  sub test_schema {
    unlink 'test.sqlite';
    require Bakesale::Schema;
    my $schema = Bakesale::Schema->connect(
      'dbi:SQLite:dbname=test.sqlite',
      undef,
      undef,
    );

    $schema->deploy;

    $schema->resultset('Cookies')->populate([
      { account_id => 1, state => 1, id => 1, type => 'tim tam',
        baked_at => 1455319258 },
      { account_id => 1, state => 1, id => 2, type => 'oreo',
        baked_at => 1455319283 },
      { account_id => 2, state => 1, id => 3, type => 'thin mint',
        baked_at => 1455319308 },
      { account_id => 1, state => 3, id => 4, type => 'samoa',
        baked_at => 1455319240 },
      { account_id => 1, state => 8, id => 5, type => 'tim tam',
        baked_at => 1455310000 },
    ]);

    $schema->resultset('States')->populate([
      { account_id => 1, type => 'cookies', state => 8 },
      { account_id => 2, type => 'cookies', state => 1 },
    ]);

    return $schema;
  }
}

package Bakesale {
  use Moose;
  with 'Ix::Processor::WithSchema';

  use Ix::Util qw(error result);

  use experimental qw(signatures postderef);
  use namespace::autoclean;

  BEGIN { Bakesale::Context->import }

  sub handler_for ($self, $method) {
    return 'pie_type_list' if $method eq 'pieTypes';
    return 'bake_pies'     if $method eq 'bakePies';
    return;
  }

  sub pie_type_list ($self, $arg = {}, $ephemera = {}) {
    my $only_tasty = delete local $arg->{tasty};
    return error('invalidArguments') if keys %$arg;

    my @flavors = qw(pumpkin apple pecan);
    push @flavors, qw(cherry eel) unless $only_tasty;

    return Bakesale::PieTypes->new({ flavors => \@flavors });
  }

  sub bake_pies ($self, $arg = {}, $ephemera = {}) {
    return error("invalidArguments")
      unless $arg->{pieTypes} && $arg->{pieTypes}->@*;

    my %is_flavor = map {; $_ => 1 }
                    $self->pie_type_list({ tasty => $arg->{tasty} })->flavors;

    my @rv;
    for my $type ($arg->{pieTypes}->@*) {
      if ($is_flavor{$type}) {
        push @rv, Bakesale::Pie->new({ flavor => $type });
      } else {
        push @rv, error(noRecipe => { requestedPie => $type })
      }
    }

    return @rv;
  }

  __PACKAGE__->meta->make_immutable;
  1;
}

package Bakesale::PieTypes {
  use Moose;
  with 'Ix::Result';

  use experimental qw(signatures postderef);
  use namespace::autoclean;

  has flavors => (
    traits   => [ 'Array' ],
    handles  => { flavors => 'elements' },
    required => 1,
  );

  sub result_type { 'pieTypes' }

  sub result_properties ($self) {
    return {
      flavors => [ $self->flavors ],
    };
  }

  __PACKAGE__->meta->make_immutable;
  1;
}

package Bakesale::Pie {
  use Moose;

  with 'Ix::Result';

  use experimental qw(signatures postderef);
  use namespace::autoclean;

  has flavor     => (is => 'ro', required => 1);
  has bake_order => (is => 'ro', default => sub { state $i; ++$i });

  sub result_type { 'pie' }
  sub result_properties ($self) {
    return { flavor => $self->flavor, bakeOrder => $self->bake_order };
  }
}

1;
