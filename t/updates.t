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

{
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

  subtest "synchronize 2->4, no limit" => sub {
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

  subtest "synchronize 2->4, limit exceeds changes" => sub {
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

  subtest "synchronize 2->4, limit equals changes" => sub {
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

  subtest "synchronize 2->4, limit requires truncation" => sub {
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

  subtest "synchronize 2->4, limit cannot be satisified in one state" => sub {
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
}

done_testing;
