use 5.20.0;

package Bakesale::Context {
  use warnings;
  use experimental qw(signatures postderef);

  sub account_id ($self) { 1 }

  our $Context = bless { } => __PACKAGE__;
}

package Bakesale {
  use Moose;
  with 'Ix::Processor';

  use List::MoreUtils qw(uniq);
  use Ix::Util qw(error result);

  use experimental qw(signatures postderef);
  use namespace::autoclean;

  BEGIN { Bakesale::Context->import }

  has schema => (
    is => 'ro',
    required => 1,
  );

  sub handler_for ($self, $method) {
    return 'pie_type_list' if $method eq 'pieTypes';
    return 'bake_pies'     if $method eq 'bakePies';
    return 'get_cookies'   if $method eq 'getCookies';
    return 'set_cookies'   if $method eq 'setCookies';
    return;
  }

  sub get_cookies ($self, $arg = {}, $ephemera = {}) {
    my $account_id = $Bakesale::Context::Context->account_id;

    my $ids   = $arg->{ids};
    my $props = $arg->{properties}; # something to pass to HashInflater?
    my $since = $arg->{sinceState};

    # TODO validate $props

    my @rows = $self->schema->resultset('Cookies')->search(
      {
        account_id => $account_id,
        (defined $since ? (state => { '>' => $since }) : ()),
        ($ids ? (cookieid => $ids) : ()),
      },
      {
        ($props ? (select => [ uniq(id => @$props) ]) : ()),
        result_class => 'DBIx::Class::ResultClass::HashRefInflator',
      },
    )->all;

    # TODO: populate notFound result property

    return result(cookies => {
      state => 10,
      list  => \@rows,
      notFound => undef,
    });
  }

  sub set_cookies ($self, $arg = {}, $ephemera = {}) {
    my $cookies_rs = $self->schema->resultset('Cookies');
    $cookies_rs->ix_set($arg, $ephemera);
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
