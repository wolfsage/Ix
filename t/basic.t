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
Bakesale::Test->load_trivial_dataset($app->processor->schema_connection);

{
  my $res = $jmap_tester->request([
    [ pieTypes => { tasty => 1 } ],
    [ pieTypes => { tasty => 0 } ],
  ]);

  cmp_deeply(
    $jmap_tester->strip_json_types( $res->sentence(0)->as_pair ),
    [ pieTypes => { flavors => [ qw(pumpkin apple pecan) ] } ],
    "first call response: as expected",
  );

  cmp_deeply(
    $jmap_tester->strip_json_types( $res->paragraph(1)->single->as_pair ),
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
    $jmap_tester->strip_json_types( $pie1->as_pairs ),
    [
      [ pieTypes => { flavors => [ qw(pumpkin apple pecan) ] } ],
    ],
    "pieTypes call 1 reply: as expected",
  );

  cmp_deeply(
    $jmap_tester->strip_json_types( $bake->as_pairs ),
    [
      [ pie   => { flavor => 'apple', bakeOrder => 1 } ],
      [ error => { type => 'noRecipe', requestedPie => 'eel' } ],
    ],
    "bakePies call reply: as expected",
  );

  cmp_deeply(
    $jmap_tester->strip_json_types( $pie2->as_pairs ),
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

  isa_ok(
    $res->as_struct->[0][1]{list}[0]{id},
    'JSON::Typist::String',
    "we return ids as strings",
  );

  cmp_deeply(
    $jmap_tester->strip_json_types( $res->as_pairs ),
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
    [ getCookies => { ids => [ 4, -1 ], properties => [ qw(type) ] } ],
  ]);

  isa_ok(
    $res->as_struct->[0][1]{list}[0]{id},
    'JSON::Typist::String',
    "we return ids as strings",
  );

  cmp_deeply(
    $jmap_tester->strip_json_types( $res->as_pairs ),
    [
      [
        cookies => {
          notFound => [ "-1" ],
          state => 8,
          list  => [
            { id => 4, type => 'samoa' }, # baked_at => 1455319240 },
          ],
        },
      ],
    ],
    "a getFoos call with notFound entries",
  );
}

{
  my $res = $jmap_tester->request([
    [ getCakes => { } ],
  ]);

  cmp_deeply(
    $jmap_tester->strip_json_types( $res->as_pairs ),
    [
      [
        error => {
          type => 'invalidArguments',
          description => "required parameter 'ids' not present",
        }
      ]
    ],
    "a getCakes call without 'ids' argument",
  );
}

{
  my $res = $jmap_tester->request([
    [ setCookies => { ifInState => 3, destroy => [ 4 ] } ],
  ]);

  cmp_deeply(
    $jmap_tester->strip_json_types( $res->as_pairs ),
    [
      [ error => { type => 'stateMismatch' } ],
    ],
    "setCookies respects ifInState",
  );
}

my @created_ids;

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
    $jmap_tester->strip_json_types( $res->as_pairs ),
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
            blue   => superhashof({
              type => 'invalidProperties',
              propertyErrors => { type => 'no value given for required field' }
            }),
          },
          updated => [ 1 ],
          notUpdated => {
            2 => superhashof({
              type => 'invalidProperties',
              propertyErrors => { delicious => "unknown property" },
            }),
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

  my $struct = $jmap_tester->strip_json_types( $set->arguments );
  @created_ids = map {; $struct->{created}{$_}{id} }
                 $set->created_creation_ids;
}

{
  my $res = $jmap_tester->request([
    [ getCookieUpdates => { sinceState => 8 } ],
  ]);

  cmp_deeply(
    $jmap_tester->strip_json_types( $res->as_pairs ),
    [
      [
        cookieUpdates => {
          oldState => 8,
          newState => 9,
          hasMoreUpdates => bool(0),
          changed  => bag(1, @created_ids),
          removed  => bag(4),
        },
      ],
    ],
    "updates can be got",
  ) or diag explain( $res->as_pairs );
}

subtest "invalid sinceState" => sub {
  subtest "too high" => sub {
    my $res = $jmap_tester->request([
      [ getCookieUpdates => { sinceState => 999 } ],
    ]);

    cmp_deeply(
      $jmap_tester->strip_json_types( $res->single_sentence->as_pair ),
      [ error => superhashof({ type => 'invalidArguments' }) ],
      "updates can't be got for invalid sinceState",
    ) or diag explain($res);
  };

  subtest "too low" => sub {
    my $res = $jmap_tester->request([
      [ getCookieUpdates => { sinceState => 1 } ],
    ]);

    cmp_deeply(
      $jmap_tester->strip_json_types( $res->single_sentence->as_pair ),
      [ error => superhashof({ type => 'cannotCalculateChanges' }), ],
      "updates can't be got for invalid sinceState",
    ) or diag explain($res);
  };
};

{
  my $get_res = $jmap_tester->request([
    [ getCookies => { ids => [ 1, @created_ids ] } ],
  ]);

  my $res = $jmap_tester->request([
    [ getCookieUpdates => { sinceState => 8, fetchRecords => 1 } ],
  ]);

  my $get_payloads = $jmap_tester->strip_json_types(
    $get_res->single_sentence->arguments
  );

  cmp_deeply(
    $jmap_tester->strip_json_types( $res->as_pairs ),
    [
      [
        cookieUpdates => {
          oldState => 8,
          newState => 9,
          hasMoreUpdates => bool(0),
          changed  => bag(1, @created_ids),
          removed  => bag(4),
        },
      ],
      [
        cookies => {
          $get_payloads->%*,
          list => bag( $get_payloads->{list}->@* ),
        },
      ],
    ],
    "updates can be got (with implicit fetch)",
  ) or diag explain( $jmap_tester->strip_json_types( $res->as_pairs ) );
}

{
  my $res = $jmap_tester->request([
    [
      setCakes => {
        ifInState => 0,
        create    => {
          yum => { type => 'wedding', layer_count => 4, recipeId => 1 },
          yow => { type => 'croquembouche', layer_count => 99, recipeId => 1 }
        }
      },
    ],
  ]);

  cmp_deeply(
    $jmap_tester->strip_json_types( $res->as_pairs ),
    [
      [
        cakesSet => superhashof({
          created => {
            yum => superhashof({ baked_at => ignore() }),
          },
          notCreated => {
            yow => superhashof({
              type => 'invalidProperties',
              propertyErrors => { layer_count => re(qr/above max/) },
            }),
          },
        }),
      ],
    ],
    "we can bake cakes",
  );
}

subtest "passing in a boolean" => sub {
  my $res = $jmap_tester->request([
    [
      setCakeRecipes => {
        create => {
          boat => {
            type          => 'cake boat',
            avg_review    => 0,
            is_delicious  => \0,
          }
        },
      },
    ],
  ]);

  cmp_deeply(
    $jmap_tester->strip_json_types( $res->as_pairs ),
    [
      [ cakeRecipesSet => superhashof({ created => superhashof({}) }) ],
    ],
    "made an object with a boolean property value",
  ) or note(explain($res->as_pairs));

  my $id = $res->single_sentence->as_set->created_id('boat');

  my $get = $jmap_tester->request([
    [ getCakeRecipes => { ids => [ "$id" ] } ]
  ]);

  cmp_deeply(
    $jmap_tester->strip_json_types( $get->as_pairs ),
    [
      [
        cakeRecipes => superhashof({
          list => [ superhashof({ id => "$id", is_delicious => bool(0) }) ],
        }),
      ],
    ],
    "created with the right truthiness",
  ) or note(explain($res->as_pairs));
};

subtest "make a recipe and a cake in one exchange" => sub {
  my $res = $jmap_tester->request([
    [
      setCakeRecipes => {
        create => {
          pav => { type => 'pavlova', avg_review => 50 }
        },
      },
    ],
    [
      setCakes => {
        create    => {
          magic => { type => 'eggy', layer_count => 2, recipeId => '#pav' },
        }
      },
    ],
  ]);

  cmp_deeply(
    $jmap_tester->strip_json_types( $res->as_pairs ),
    [
      [ cakeRecipesSet => superhashof({}) ],
      [ cakesSet       => superhashof({}) ],
    ],
    "we can bake cakes with recipes in one go",
  ) or note(explain($res->as_pairs));
};

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
    $jmap_tester->strip_json_types( $res->as_pairs ),
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
