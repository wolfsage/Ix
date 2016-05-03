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

# Things to test:
#   * no changes
#   * since too low
#   * since too high
#   * no limit
#   * limit higher than changes
#   * limit higher than changes, by 1 (because of implementation detail)
#   * limit reached and trimming works
#   * limit reached and trimming does not work

{
  # First up, we are going to set up fudge distinct states, each with 10
  # updates. -- rjbs, 2016-05-03
  my $last_set_res;
  for my $type (qw(sugar anzac spritz fudge)) {
    $last_set_res = $jmap_tester->request([
      [
        setCookies => {
          create => { map {; $_ => { type => $type } } (0 .. 10) }
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
    ok( ! $arg->{hasMoreUpdate}, "no more updates");
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
}

done_testing;
