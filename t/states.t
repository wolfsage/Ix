use 5.20.0;
use warnings;
use utf8;
use experimental qw(lexical_subs signatures postderef refaliasing);

use lib 't/lib';

use Bakesale;
use Bakesale::App;
use Bakesale::Schema;
use JSON;
use Test::Deep;
use Test::Deep::JType;
use Test::More;
use Unicode::Normalize;
use Ix::Util qw(ix_new_id);
use Data::Dumper;

my $no_updates = any({}, undef);

my ($app, $jmap_tester) = Bakesale::Test->new_test_app_and_tester;
\my %account = Bakesale::Test->load_trivial_account($app->processor->schema_connection);

$jmap_tester->_set_cookie('bakesaleUserId', $account{users}{rjbs});

my %children;
my $parent_pid = $$;

sub with_child ($block) :prototype(&) {
  my $res = fork;
  if ($res) {
    $children{$res} = 1;

    return $res;
  }

  $block->();

  exit;
}

sub end_child ($child) {
  kill 'TERM' => $child;
}

END {
  for my $k (keys %children) {
    waitpid($k, 0);
  }
}

# Get some initial state
my $res = $jmap_tester->request([
  [
    setCookies => {
      create => { raw => { type => 'dough', baked_at => undef } },
    },
  ],
]);

cmp_deeply(
  $res->single_sentence->arguments,
  superhashof({
        created => { raw => { id => re(qr/\S/), expires_at => ignore(), delicious => ignore() } },
  }),
  "created a cookie",
) or diag(explain($jmap_tester->strip_json_types( $res->as_pairs )));

my $state = $res->single_sentence->arguments->{newState};
ok(defined($state), 'got new state');

# Now make two calls that will happen simultaneously by creating a lock on
# the cookies table that will prevent either call from succeeding until
# the lock is complete. Then release the lock after standing up two children
# that are in the middle of making such a call. At the end, we should see
# two state increases, and two different cookies created at two different
# states.

my $done = 0;
$SIG{'USR1'} = sub { $done++; };

my $lock = with_child {
  my $schema = $app->processor->schema_connection;

  $schema->txn_do(sub {
    $schema->storage->dbh->do("LOCK TABLE cookies IN ACCESS EXCLUSIVE MODE");
    sleep 10;
  });

};

# Our first set cookies
with_child {
  my $res = $jmap_tester->request([
    [
      setCookies => {
        create => { raw => { type => 'first', baked_at => undef } },
      },
    ],
  ]);

  unless ($res->is_success) {
    warn "First child failed to setCookies: " . Dumper $res->as_stripped_struct;
  }

  # Signal our parent we're done
  kill 'USR1' => $parent_pid;
};

# Our second set cookies
with_child {
  my $res = $jmap_tester->request([
    [
      setCookies => {
        create => { raw => { type => 'second', baked_at => undef } },
      },
    ],
  ]);

  unless ($res->is_success) {
    warn "Second child failed to setCookies: " . Dumper $res->as_stripped_struct;
  }

  # Signal our parent we're done
  kill 'USR1' => $parent_pid;
};

is($done, 0, 'no process completed yet');
end_child($lock);

for my $k (keys %children) {
  waitpid($k, 0);
}

is($done, 2, '2 children report they are complete');

# This should give us two cookies, with state increasing by two
$res = $jmap_tester->request([
  [ getCookieUpdates => {
    sinceState => $state,
  } ],
]);

my $new_state = $res->single_sentence->arguments->{newState};
is($new_state, $state + 2, 'state bumped twice');

# Test should also try state + 1 and ensure it gets only
# one cookie back

done_testing;
