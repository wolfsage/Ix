use 5.20.0;
use warnings;
use experimental qw(signatures postderef);

use lib 't/lib';

use Bakesale;
use Bakesale::App;
use Bakesale::Schema;
use Test::Deep;
use Test::More;

my ($app, $jmap_tester) = Bakesale::Test->new_test_app_and_tester;
my $admin_id = Bakesale::Test->load_single_user($app->processor->schema_connection);
$jmap_tester->_set_cookie('bakesaleUserId', $admin_id);

subtest "simple state comparisons" => sub {
  # First up, we are going to set up fudge distinct states, each with 10
  # updates. -- rjbs, 2016-05-03
  my $last_set_res;
  for my $type (qw(sugar anzac spritz fudge)) {
    $last_set_res = $jmap_tester->request([
      [
        setCookies => {
          create => { map {; $_ => { type => $type } } (1 .. 10) }
        }
      ],
    ]);
  }

  my $state = $last_set_res->single_sentence->as_set->new_state . "";

  subtest "synchronize to current state: no-op" => sub {
    my $res = $jmap_tester->request([
      [ getCookieUpdates => { sinceState => "4" } ]
    ]);

    my ($type, $arg) = $res->single_sentence->as_struct->@*;
    is($type, 'cookieUpdates', 'cookie updates!!');

    is($arg->{oldState}, 4, "old state: 4");
    is($arg->{newState}, 4, "new state: 4");
    ok( ! $arg->{hasMoreUpdates}, "no more updates");
    ok(! $arg->{changed}->@*, "no items changed");
    ok(! $arg->{removed}->@*, "no items removed");
  };

  subtest "synchronize from lowest state on file" => sub {
    my $res = $jmap_tester->request([
      [ getCookieUpdates => { sinceState => "0" } ]
    ]);

    my ($type, $arg) = $res->single_sentence->as_struct->@*;
    is($type, 'error', 'can not sync from "0" state');

    is($arg->{type}, "cannotCalculateChanges", "error type");
  };

  subtest "synchronize from the future" => sub {
    my $res = $jmap_tester->request([
      [ getCookieUpdates => { sinceState => "8" } ]
    ]);

    my ($type, $arg) = $res->single_sentence->as_struct->@*;
    is($type, 'error', 'can not sync from future state');

    is($arg->{type}, "invalidArguments", "error type");
  };

  subtest "synchronize (2 to 4), no maxChanges" => sub {
    my $res = $jmap_tester->request([
      [ getCookieUpdates => { sinceState => "2" } ]
    ]);

    my ($type, $arg) = $res->single_sentence->as_struct->@*;
    is($type, 'cookieUpdates', 'cookie updates!!');

    is($arg->{oldState}, 2, "old state: 2");
    is($arg->{newState}, 4, "new state: 4");
    ok( ! $arg->{hasMoreUpdates}, "no more updates");
    is($arg->{changed}->@*, 20, "20 items changed");
    ok(! $arg->{removed}->@*,   "no items removed");
  };

  subtest "synchronize (2 to 4), maxChanges exceeds changes" => sub {
    my $res = $jmap_tester->request([
      [ getCookieUpdates => { sinceState => "2", maxChanges => 30 } ]
    ]);

    my ($type, $arg) = $res->single_sentence->as_struct->@*;
    is($type, 'cookieUpdates', 'cookie updates!!');

    is($arg->{oldState}, 2, "old state: 2");
    is($arg->{newState}, 4, "new state: 4");
    ok( ! $arg->{hasMoreUpdates}, "no more updates");
    is($arg->{changed}->@*, 20, "20 items changed");
    ok(! $arg->{removed}->@*,   "no items removed");
  };

  subtest "synchronize (2 to 4), maxChanges equals changes" => sub {
    my $res = $jmap_tester->request([
      [ getCookieUpdates => { sinceState => "2", maxChanges => 20 } ]
    ]);

    my ($type, $arg) = $res->single_sentence->as_struct->@*;
    is($type, 'cookieUpdates', 'cookie updates!!');

    is($arg->{oldState}, 2, "old state: 2");
    is($arg->{newState}, 4, "new state: 4");
    ok( ! $arg->{hasMoreUpdates}, "no more updates");
    is($arg->{changed}->@*, 20, "20 items changed");
    ok(! $arg->{removed}->@*,   "no items removed");
  };

  subtest "synchronize (2 to 4), maxChanges requires truncation" => sub {
    my $res = $jmap_tester->request([
      [ getCookieUpdates => { sinceState => "2", maxChanges => 15 } ]
    ]);

    my ($type, $arg) = $res->single_sentence->as_struct->@*;
    is($type, 'cookieUpdates', 'cookie updates!!');

    is($arg->{oldState}, 2, "old state: 2");
    is($arg->{newState}, 3, "new state: 3");
    ok($arg->{hasMoreUpdates},   "more updates to get");
    is($arg->{changed}->@*, 10, "10 items changed");
    ok(! $arg->{removed}->@*,   "no items removed");
  };

  subtest "synchronize (2 to 4), maxChanges must be exceeded" => sub {
    my $res = $jmap_tester->request([
      [ getCookieUpdates => { sinceState => "2", maxChanges => 8 } ]
    ]);

    my ($type, $arg) = $res->single_sentence->as_struct->@*;
    is($type, 'cookieUpdates', 'cookie updates!!');

    is($arg->{oldState}, 2, "old state: 2");
    is($arg->{newState}, 3, "new state: 3");
    ok($arg->{hasMoreUpdates},   "more updates to get");
    is($arg->{changed}->@*, 10, "10 items changed");
    ok(! $arg->{removed}->@*,   "no items removed");
  };
};

subtest "complex state comparisons" => sub {
  # Okay, here we're going to have two kinds of results, where changing the
  # parent row causes the child to seem out of sync.  Specifically, we have
  # Cakes and CakeRecipes.  If a cake changes, it has changed.  If a recipe has
  # changed, all the cakes of that recipe are also changed.  This is a rough
  # approximation of the logic that will govern mailing list members and lists.
  # -- rjbs, 2016-05-04
  my %recipe_id;
  subtest "create 5 recipes" => sub {
    for my $n (1..5) {
      my $cr_res = $jmap_tester->request([
        [
          setCakeRecipes => {
            create => { $n => { type => "recipe-$n", avg_review => 75 } }
          },
        ],
      ]);

      my $recipe_res = $jmap_tester->strip_json_types(
        $cr_res->single_sentence->as_struct->[1]
      );

      $recipe_id{$n} = $recipe_res->{created}{$n}{id};

      my $cr_state = $cr_res->single_sentence->as_set->new_state . "";
      is($cr_state, $n, "after creating recipe $n, state is $n");
    }
  };

  my %cake_id;
  subtest "create 20 cakes" => sub {
    my $last_set_res;
    for my $layer_count (1 .. 4) {
      $last_set_res = $jmap_tester->request([
        [
          setCakes => {
            create => { map {; $_ => {
              type     => "test $layer_count/$_",
              recipe_id => $recipe_id{$_},
              layer_count => $layer_count,
            } } (1 .. 5) }
          }
        ],
      ]);

      my $payload = $jmap_tester->strip_json_types(
        $last_set_res->single_sentence->as_struct->[1]
      );

      for my $recipe (1 .. 5) {
        $cake_id{"C${layer_count}R$recipe"}
          = $payload->{created}{$recipe}{id};
      }
    }

    my $state = $last_set_res->single_sentence->as_set->new_state . "";
    is($state, "4-5", "four cake sets on recipe state 5; state is 4-5");
  };

  my %cake_id_rev = reverse %cake_id;

  subtest "synchronize to current state: no-op" => sub {
    my $res = $jmap_tester->request([
      [ getCakeUpdates => { sinceState => "4-5" } ]
    ]);

    my ($type, $arg) = $res->single_sentence->as_struct->@*;
    is($type, 'cakeUpdates', 'cake updates!!');

    is($arg->{oldState}, '4-5', "old state: 4-5");
    is($arg->{newState}, '4-5', "new state: 4-5");
    ok( ! $arg->{hasMoreUpdates}, "no more updates");
    ok(! $arg->{changed}->@*, "no items changed");
    ok(! $arg->{removed}->@*, "no items removed");
  };

  subtest "synchronize from non-compound state" => sub {
    my $res = $jmap_tester->request([
      [ getCakeUpdates => { sinceState => "2" } ]
    ]);

    my ($type, $arg) = $res->single_sentence->as_struct->@*;
    is($type, 'error', 'can not sync from non-compount state');

    is($arg->{type}, "invalidArguments", "error type");
  };

  subtest "synchronize from too-low lhs state" => sub {
    my $res = $jmap_tester->request([
      [ getCakeUpdates => { sinceState => "0-3" } ]
    ]);

    my ($type, $arg) = $res->single_sentence->as_struct->@*;
    is($type, 'error', 'can not sync from (one-part) too-low state');

    is($arg->{type}, "cannotCalculateChanges", "error type");
  };

  subtest "synchronize from too-low rhs state" => sub {
    my $res = $jmap_tester->request([
      [ getCakeUpdates => { sinceState => "3-0" } ]
    ]);

    my ($type, $arg) = $res->single_sentence->as_struct->@*;
    is($type, 'error', 'can not sync from (one-part) too-low state');

    is($arg->{type}, "cannotCalculateChanges", "error type");
  };

  subtest "synchronize (3-5 to 4-5), no maxChanges" => sub {
    my $res = $jmap_tester->request([
      [ getCakeUpdates => { sinceState => "3-5" } ]
    ]);

    my ($type, $arg) = $res->single_sentence->as_struct->@*;
    is($type, 'cakeUpdates', 'cake updates!!');

    is($arg->{oldState}, '3-5', "old state: 3-5");
    is($arg->{newState}, '4-5', "new state: 4-5");
    ok( ! $arg->{hasMoreUpdates}, "no more updates");
    is($arg->{changed}->@*, 5, "5 items changed");

    is_deeply(
      [ sort $arg->{changed}->@* ],
      [ sort @cake_id{qw( C4R1 C4R2 C4R3 C4R4 C4R5 )} ],
      "the five expected items updated",
    );

    ok(! $arg->{removed}->@*,   "no items removed");
  };

  subtest "synchronize (4-4 to 4-5), no maxChanges" => sub {
    my $res = $jmap_tester->request([
      [ getCakeUpdates => { sinceState => "4-4" } ]
    ]);

    my ($type, $arg) = $res->single_sentence->as_struct->@*;
    is($type, 'cakeUpdates', 'cake updates!!');

    is($arg->{oldState}, '4-4', "old state: 4-4");
    is($arg->{newState}, '4-5', "new state: 4-5");
    ok( ! $arg->{hasMoreUpdates}, "no more updates");
    is($arg->{changed}->@*, 4, "4 items changed");

    is_deeply(
      [ sort $arg->{changed}->@* ],
      [ sort @cake_id{qw( C1R5 C2R5 C3R5 C4R5 )} ],
      "the five expected items updated",
    );

    ok(! $arg->{removed}->@*,   "no items removed");
  };

  for my $test (
    [ "sync (3-4 to 4-5), no maxChanges",              {} ],
    [ "sync (3-4 to 4-5), maxChanges exceeds updates", { maxChanges => 10 } ],
    [ "sync (3-4 to 4-5), maxChanges qeuals updates",  { maxChanges =>  8 } ],
  ) {
    subtest $test->[0] => sub {
      my $res = $jmap_tester->request([
        [ getCakeUpdates => { sinceState => "3-4", $test->[1]->%* } ]
      ]);

      my ($type, $arg) = $res->single_sentence->as_struct->@*;
      is($type, 'cakeUpdates', 'cake updates!!');

      is($arg->{oldState}, '3-4', "old state: 3-4");
      is($arg->{newState}, '4-5', "new state: 4-5");
      ok( ! $arg->{hasMoreUpdates}, "no more updates");
      is($arg->{changed}->@*, 8, "8 items changed");

      is_deeply(
        [ sort $arg->{changed}->@* ],
        [ sort @cake_id{qw( C4R1 C4R2 C4R3 C4R4 C4R5
                            C1R5 C2R5 C3R5 )} ],
        "the eight expected items updated",
      );

      ok(! $arg->{removed}->@*,   "no items removed");
    };
  }

  subtest "sync (3-4 to 4-5), maxChanges forces 2 passes" => sub {
    my %changed;
    my $mid_state;
    subtest "first pass at small-window update" => sub {
      my $res = $jmap_tester->request([
        [ getCakeUpdates => { sinceState => "3-4", maxChanges => 5 } ]
      ]);

      my ($type, $arg) = $res->single_sentence->as_struct->@*;
      is($type, 'cakeUpdates', 'cake updates!!');

      is($arg->{oldState}, '3-4', "old state: 3-4");
      ok(
        $arg->{newState} ne $arg->{oldState},
        "new state: $arg->{newState}",
      );
      ok($arg->{hasMoreUpdates},  "more updates await");
      ok(! $arg->{removed}->@*,   "no items removed");

      my @changed = $arg->{changed}->@*;
      cmp_ok(@changed, '<=', 5, "<= 5 items changed");

      $changed{ $cake_id_rev{$_} }++ for @changed;
      $mid_state = $arg->{newState};
    };

    subtest "second pass at small-window update" => sub {
      my $res = $jmap_tester->request([
        [ getCakeUpdates => { sinceState => $mid_state, maxChanges => 5 } ]
      ]);

      my ($type, $arg) = $res->single_sentence->as_struct->@*;
      is($type, 'cakeUpdates', 'cake updates!!');

      is($arg->{oldState}, $mid_state, "old state: $mid_state");
      ok(! $arg->{hasMoreUpdates},  "no more updates");
      ok(! $arg->{removed}->@*,   "no items removed");

      my @changed = $arg->{changed}->@*;
      cmp_ok(@changed, '<=', 5, "<= 5 items changed");

      $changed{ $cake_id_rev{$_} }++ for $arg->{changed}->@*;
    };

    is(keys %changed, 8, "eight total updates (with maybe some dupes)");
    is_deeply(
      [ sort keys %changed ],
      [ sort qw( C4R1 C4R2 C4R3 C4R4 C4R5 C1R5 C2R5 C3R5 ) ],
      "the eight expected items updated",
    );
  };

  subtest "sync (3-4 to 4-5), maxChanges smaller than first window" => sub {
    my %changed;
    my $mid_state;
    subtest "first pass at small-window update" => sub {
      my $res = $jmap_tester->request([
        [ getCakeUpdates => { sinceState => "3-4", maxChanges => 3 } ]
      ]);

      my ($type, $arg) = $res->single_sentence->as_struct->@*;
      is($type, 'cakeUpdates', 'cake updates!!');

      is($arg->{oldState}, '3-4', "old state: 3-4");
      ok(
        $arg->{newState} ne $arg->{oldState},
        "new state: $arg->{newState}",
      );
      ok($arg->{hasMoreUpdates},  "more updates await");
      ok(! $arg->{removed}->@*,   "no items removed");

      my @changed = $arg->{changed}->@*;
      cmp_ok(@changed, '<=', 5, "<= 5 items changed");

      $changed{ $cake_id_rev{$_} }++ for @changed;
      $mid_state = $arg->{newState};
    };

    subtest "second pass at small-window update" => sub {
      my $res = $jmap_tester->request([
        [ getCakeUpdates => { sinceState => $mid_state, maxChanges => 5 } ]
      ]);

      my ($type, $arg) = $res->single_sentence->as_struct->@*;
      is($type, 'cakeUpdates', 'cake updates!!');

      is($arg->{oldState}, $mid_state, "old state: $mid_state");
      ok(! $arg->{hasMoreUpdates},  "no more updates");
      ok(! $arg->{removed}->@*,   "no items removed");

      my @changed = $arg->{changed}->@*;
      cmp_ok(@changed, '<=', 5, "<= 5 items changed");

      $changed{ $cake_id_rev{$_} }++ for $arg->{changed}->@*;
    };

    is(keys %changed, 8, "eight total updates (with maybe some dupes)");
    is_deeply(
      [ sort keys %changed ],
      [ sort qw( C4R1 C4R2 C4R3 C4R4 C4R5 C1R5 C2R5 C3R5 ) ],
      "the eight expected items updated",
    );
  };
};

done_testing;
