use 5.20.0;
use warnings;
use experimental qw(signatures postderef);

use lib 't/lib';

use Bakesale;
use Bakesale::Schema;
use Test::Deep;
use Test::More;

my $conn_info = Bakesale::Test->test_schema_connect_info;

require Bakesale::App;
my $app = Bakesale::App->new->app;

use Plack::Test;

my $plack_test = Plack::Test->create($app);

use JMAP::Tester;

my $jmap_tester = JMAP::Tester->new({
  jmap_uri => 'https://localhost/jmap',
  _request_callback => sub {
    shift; $plack_test->request(@_);
  },
});

{
  my $res = $jmap_tester->request([
    [ pieTypes => { tasty => 1 } ],
    [ pieTypes => { tasty => 0 } ],
  ]);

  cmp_deeply(
    $jmap_tester->strip_json_types( $res->sentence(0)->as_struct ),
    [ pieTypes => { flavors => [ qw(pumpkin apple pecan) ] } ],
    "first call response: as expected",
  );

  cmp_deeply(
    $jmap_tester->strip_json_types( $res->paragraph(1)->single->as_struct ),
    [ pieTypes => { flavors => [ qw(pumpkin apple pecan cherry eel) ] } ],
    "second call response group: one item, as expected",
  );
}

{
  my $res = $jmap_tester->request([
    [ pieTypes => { tasty => 1 } ],
    [ bakePies => { tasty => 1, pieTypes => [ qw(apple eel pecan) ] } ],
    [ pieTypes => { tasty => 0 } ],
  ]);

  my ($pie1, $bake, $pie2) = $res->assert_n_paragraphs(3);

  cmp_deeply(
    $jmap_tester->strip_json_types( $pie1->as_struct ),
    [
      [ pieTypes => { flavors => [ qw(pumpkin apple pecan) ] } ],
    ],
    "pieTypes call 1 reply: as expected",
  );

  cmp_deeply(
    $jmap_tester->strip_json_types( $bake->as_struct ),
    [
      [ pie   => { flavor => 'apple', bakeOrder => 1 } ],
      [ error => { type => 'noRecipe', requestedPie => 'eel' } ],
    ],
    "bakePies call reply: as expected",
  );

  cmp_deeply(
    $jmap_tester->strip_json_types( $pie2->as_struct ),
    [
      [ pieTypes => { flavors => [ qw(pumpkin apple pecan cherry eel) ] } ],
    ],
    "pieTypes call 2 reply: as expected",
  );
}

{
  my $res = $jmap_tester->request([
    [ getCookies => { sinceState => 2, properties => [ qw(type) ] } ],
  ]);

  cmp_deeply(
    $jmap_tester->strip_json_types( $res->as_struct ),
    [
      [
        cookies => {
          notFound => undef,
          state => 8,
          list  => [
            { id => 4, type => 'samoa',   }, # baked_at => 1455319240 },
            { id => 5, type => 'tim tam', }, # baked_at => 1455310000 },
          ],
        },
      ],
    ],
    "a getFoos call backed by the database",
  );
}

{
  my $res = $jmap_tester->request([
    [ setCookies => { ifInState => 3, destroy => [ 4 ] } ],
  ]);

  cmp_deeply(
    $jmap_tester->strip_json_types( $res->as_struct ),
    [
      [ error => { type => 'stateMismatch' } ],
    ],
    "setCookies respects ifInState",
  );
}

{
  my $res = $jmap_tester->request([
    [
      setCookies => {
        ifInState => 8,
        create    => {
          yellow => { type => 'shortbread' },
          gold   => { type => 'anzac' },
          blue   => {},
        },
        update => {
          1 => { type => 'half-eaten tim-tam' },
          2 => { delicious => 0 },
        },
        destroy => [ 4, 3 ],
      },
    ],
  ]);

  cmp_deeply(
    $jmap_tester->strip_json_types( $res->as_struct ),
    [
      [
        cookiesSet => superhashof({
          oldState => 8,
          newState => 9,

          created => {
            yellow => { id => ignore(), baked_at => ignore() },
            gold   => { id => ignore(), baked_at => ignore() },
          },
          notCreated => {
            blue   => superhashof({ type => 'invalidRecord' }),
          },
          updated => [ 1 ],
          notUpdated => {
            2 => superhashof({ type => 'invalidRecord' }),
          },
          destroyed => [ 4 ],
          notDestroyed => {
            3 => superhashof({ type => ignore() }),
          },
        }),
      ],
    ],
    "we can create cookies with setCookies",
  );

  my $set = $res->single_sentence->as_set;

  is($set->old_state, 8, "old state is 8");
  is($set->new_state, 9, "new state is 9");

  cmp_deeply(
    [ sort $set->created_creation_ids ],
    [ qw(gold yellow) ],
    "created the things we expected",
  );
}

{
  my $res = $jmap_tester->request([
    [ getCookieUpdates => { sinceState => 8 } ],
  ]);

  cmp_deeply(
    $jmap_tester->strip_json_types( $res->as_struct ),
    [
      [
        cookieUpdates => {
          oldState => 8,
          newState => 9,
          hasMoreUpdates => bool(0),
          changed  => bag(1, 6, 7),
          removed  => bag(4),
        },
      ],
    ],
    "updates can be got",
  ) or diag explain( $res->as_struct );
}

{
  my $get_res = $jmap_tester->request([
    [ getCookies => { ids => [ 1, 6, 7 ] } ],
  ]);

  my $res = $jmap_tester->request([
    [ getCookieUpdates => { sinceState => 8, fetchRecords => 1 } ],
  ]);

  cmp_deeply(
    $jmap_tester->strip_json_types( $res->as_struct ),
    [
      [
        cookieUpdates => {
          oldState => 8,
          newState => 9,
          hasMoreUpdates => bool(0),
          changed  => bag(1, 6, 7),
          removed  => bag(4),
        },
      ],
      $jmap_tester->strip_json_types( $get_res->single_sentence->as_struct ),
    ],
    "updates can be got (with implicit fetch)",
  ) or diag explain( $jmap_tester->strip_json_types( $res->as_struct ) );
}

{
  my $res = $jmap_tester->request([
    [
      setCakes => {
        ifInState => 1,
        create    => {
          yum => { type => 'wedding', layer_count => 4 }
        }
      },
    ],
  ]);

  cmp_deeply(
    $jmap_tester->strip_json_types( $res->as_struct ),
    [
      [
        cakesSet => superhashof({
          created => {
            yum => superhashof({ baked_at => ignore() }),
          }
        }),
      ],
    ],
    "we can bake cakes",
  );
}

{
  my $res = $jmap_tester->request([
    [
      setCookies => {
        ifInState => 9,
        destroy   => [ 3 ],
        create    => { blue => {} },
        update    => { 2 => { delicious => 0 } },
      },
    ],
  ]);

  cmp_deeply(
    $jmap_tester->strip_json_types( $res->as_struct ),
    [
      [
        cookiesSet => superhashof({
          oldState => 9,
          newState => 9,

          notCreated   => { blue => ignore() },
          notUpdated   => { 2    => ignore() },
          notDestroyed => { 3    => ignore() },
        }),
      ],
    ],
    "no state change when no destruction",
  );
}

done_testing;
