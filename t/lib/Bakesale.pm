use 5.20.0;
use warnings;
use experimental qw(lexical_subs signatures postderef);

package Bakesale::Test {
  use File::Temp qw(tempdir);

  sub new_test_app_and_tester ($self) {
    require JMAP::Tester;
    require LWP::Protocol::PSGI;

    my ($user_id, $conn_info) = Bakesale::Test->test_schema_connect_info;

    my $app = Bakesale::App->new({
      connect_info => $conn_info,
    });

    state $n;
    $n++;
    LWP::Protocol::PSGI->register($app->to_app, host => 'bakesale.local:' . $n);
    my $jmap_tester = JMAP::Tester->new({
      jmap_uri => "http://bakesale.local:$n/jmap",
    });

    return ($app, $jmap_tester, $user_id);
  }

  my @TEST_DBS;
  END { $_->cleanup for @TEST_DBS; }

  sub test_schema_connect_info {
    require Test::PgMonger;
    my $db = Test::PgMonger->new->create_database;
    push @TEST_DBS, $db;

    my $schema = Bakesale->new({
      connect_info => [ $db->connect_info ],
    })->schema_connection;

    $schema->deploy;

    return [ $db->connect_info ];
  }

  sub load_single_user ($self, $schema) {
    my $user_rs = $schema->resultset('User');

    my $user1 = $user_rs->create({
      dataset_id => \q{pseudo_encrypt(nextval('key_seed_seq')::int)},
      username  => 'testadmin',
      mod_seq_created => 1,
      mod_seq_changed => 1,
    });

    return $user1->id;
  }

  sub load_trivial_dataset ($self, $schema) {
    my sub modseq ($x) { return (mod_seq_created => $x, mod_seq_changed => $x) }

    my $user_rs = $schema->resultset('User');

    my $user1 = $user_rs->create({
      dataset_id => \q{pseudo_encrypt(nextval('key_seed_seq')::int)},
      username  => 'rjbs',
      modseq(1)
    });

    $user1 = $user_rs->single({ id => $user1->id });

    my $user2 = $user_rs->create({
      dataset_id => \q{pseudo_encrypt(nextval('key_seed_seq')::int)},
      username  => 'neilj',
      modseq(1)
    });

    $user2 = $user_rs->single({ id => $user2->id });

    my $a1 = $user1->dataset_id;
    my $a2 = $user2->dataset_id;

    my @cookies = $schema->resultset('Cookie')->populate([
      { dataset_id => $a1, modseq(1), type => 'tim tam',
        baked_at => '2016-01-01T12:34:56Z', expires_at => '2016-01-03:T12:34:56Z', delicious => 'yes' },
      { dataset_id => $a1, modseq(1), type => 'oreo',
        baked_at => '2016-01-02T23:45:60Z', expires_at => '2016-01-04T23:45:60Z', delicious => 'yes', },
      { dataset_id => $a2, modseq(1), type => 'thin mint',
        baked_at => '2016-01-23T01:02:03Z', expires_at => '2016-01-25T01:02:03Z', delicious => 'yes',},
      { dataset_id => $a1, modseq(3), type => 'samoa',
        baked_at => '2016-02-01T12:00:01Z', expires_at => '2016-02-03:t12:00:01Z', delicious => 'yes', },
      { dataset_id => $a1, modseq(8), type => 'tim tam',
        baked_at => '2016-02-09T09:09:09Z', expires_at => '2016-02-11T09:09:09Z', delicious => 'yes', },
      { dataset_id => $a1, modseq(8), type => 'immortal',
        baked_at => '2016-02-10T09:09:09Z', expires_at => '2016-02-11T09:09:09Z', delicious => 'yes', },
    ]);

    my @recipes = $schema->resultset('CakeRecipe')->populate([
      { dataset_id => $a1, modseq(1), type => 'seven-layer', avg_review => 91, is_delicious => 1 },
    ]);

    $schema->resultset('State')->populate([
      { dataset_id => $a1, type => 'cookies', lowest_mod_seq => 1, highest_mod_seq => 8 },
      { dataset_id => $a2, type => 'cookies', lowest_mod_seq => 1, highest_mod_seq => 1 },
      { dataset_id => $a1, type => 'users',   lowest_mod_seq => 1, highest_mod_seq => 1 },
      { dataset_id => $a2, type => 'users',   lowest_mod_seq => 1, highest_mod_seq => 1 },
    ]);

    return {
      datasets => { rjbs => $a1, neilj => $a2 },
      users    => { rjbs => $user1->id, neilj => $user2->id },
      recipes  => { 1 => $recipes[0]->id },
      cookies  => { map {; ($_+1) => $cookies[$_]->id } keys @cookies },
    };
  }
}

package Bakesale {
  use Moose;
  with 'Ix::Processor';

  use Bakesale::Context;
  use Data::GUID qw(guid_string);

  use experimental qw(signatures postderef);
  use namespace::autoclean;

  sub file_exception_report ($self, $ctx, $exception) {
    Carp::cluck( "EXCEPTION!!" );
    return guid_string();
  }

  sub connect_info;
  has connect_info => (
    lazy    => 1,
    traits  => [ 'Array' ],
    handles => { connect_info => 'elements' },
    default => sub {
      Bakesale::Test->test_schema_connect_info;
    },
  );

  sub get_context ($self, $arg) {
    Bakesale::Context->new({
      user_id   => $arg->{user_id},
      schema    => $self->schema_connection,
      processor => $self,
    });
  }

  sub get_system_context ($self, $dataset_id) {
    Bakesale::Context::System->new({
      dataset_id => $dataset_id,
      schema    => $self->schema_connection,
      processor => $self,
    });
  }

  sub context_from_plack_request ($self, $req) {
    my $user_id = $req->cookies->{bakesaleUserId};
    return $self->get_context({ user_id => $user_id // 1 });
  }

  sub schema_class { 'Bakesale::Schema' }

  sub handler_for ($self, $method) {
    return 'pie_type_list' if $method eq 'pieTypes';
    return 'bake_pies'     if $method eq 'bakePies';
    return;
  }

  sub pie_type_list ($self, $ctx, $arg = {}) {
    my $only_tasty = delete local $arg->{tasty};
    return $ctx->error('invalidArguments') if keys %$arg;

    my @flavors = qw(pumpkin apple pecan);
    push @flavors, qw(cherry eel) unless $only_tasty;

    return Bakesale::PieTypes->new({ flavors => \@flavors });
  }

  sub bake_pies ($self, $ctx, $arg = {}) {
    return $ctx->error("invalidArguments")
      unless $arg->{pieTypes} && $arg->{pieTypes}->@*;

    my %is_flavor = map {; $_ => 1 }
                    $self->pie_type_list($ctx, { tasty => $arg->{tasty} })->flavors;

    my @rv;
    for my $type ($arg->{pieTypes}->@*) {
      if ($is_flavor{$type}) {
        push @rv, Bakesale::Pie->new({ flavor => $type });
      } else {
        push @rv, $ctx->error(noRecipe => { requestedPie => $type })
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
