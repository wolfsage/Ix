use 5.20.0;
use warnings;
use experimental qw(signatures postderef);

use lib 't/lib';

use Bakesale;
use Bakesale::Schema;
use Test::Deep;
use Test::More;

my $Bakesale = Bakesale->new;
Bakesale::Test->load_trivial_dataset($Bakesale->schema_connection);

my $ctx = $Bakesale->get_context({
  userId => 1,
});

{
  my $res = $ctx->process_request([
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
}

{
  my $res = $ctx->process_request([
    [ pieTypes => { tasty => 1 }, 'a' ],
    [ bakePies => { tasty => 1, pieTypes => [ qw(apple eel pecan) ] }, 'b' ],
    [ pieTypes => { tasty => 0 }, 'c' ],
  ]);

  is_deeply(
    $res,
    [
      [ pieTypes => { flavors => [ qw(pumpkin apple pecan) ] }, 'a' ],
      [ pie   => { flavor => 'apple', bakeOrder => 1 }, 'b' ],
      [ error => { type => 'noRecipe', requestedPie => 'eel' }, 'b' ],
      [ pieTypes => { flavors => [ qw(pumpkin apple pecan cherry eel) ] }, 'c' ],
    ],
    "a call with an error and a multi-value result",
  ) or diag explain($res);
}

{
  my $res = $ctx->process_request([
    [ getCookies => { sinceState => 2, properties => [ qw(type) ] }, 'a' ],
  ]);

  is_deeply(
    $res,
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
        'a',
      ],
    ],
    "a getFoos call backed by the database",
  ) or diag explain($res);
}

{
  my $res = $ctx->process_request([
    [ setCookies => { ifInState => 3, destroy => [ 4 ] }, 'a' ],
  ]);

  is_deeply(
    $res,
    [
      [ error => { type => 'stateMismatch' }, 'a' ],
    ],
    "setCookies respects ifInState",
  ) or diag explain($res);
}

my @created_ids;
{
  my $res = $ctx->process_request([
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
      'a'
    ],
  ]);

  cmp_deeply(
    $res,
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
        'a'
      ],
    ],
    "we can create cookies with setCookies",
  ) or diag explain($res);

  @created_ids = map {; $_->{id} } values %{ $res->[0][1]{created} };

  my @rows = $ctx->schema->resultset('Cookie')->search(
    { accountId => 1 },
    {
      order_by => 'id',
      result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    },
  );

  cmp_deeply(
    \@rows,
    [
      superhashof({ dateDeleted => undef, id => 1, type => 'half-eaten tim-tam' }),
      superhashof({ dateDeleted => undef, id => 2, type => 'oreo' }),
      superhashof({ dateDeleted => re(qr/\A[0-9]{4}-/), id => 4, type => 'samoa' }),
      superhashof({ dateDeleted => undef, id => 5, type => 'tim tam' }),
      superhashof({ dateDeleted => undef, id => any(@created_ids), type => any(qw(shortbread anzac)) }),
      superhashof({ dateDeleted => undef, id => any(@created_ids), type => any(qw(shortbread anzac)) }),
    ],
    "the db matches our expectations",
  ) or diag explain(\@rows);

  my $state = $ctx->schema->resultset('State')->search({
    accountId => 1,
    type => 'cookies',
  })->first;

  is($state->highestModSeq, 9, "state ended got updated just once");
}

{
  my $res = $ctx->process_request([
    [ getCookieUpdates => { sinceState => 8 }, 'a' ],
  ]);

  cmp_deeply(
    $res,
    [
      [
        cookieUpdates => {
          oldState => 8,
          newState => 9,
          hasMoreUpdates => bool(0),
          changed  => bag(1, @created_ids),
          removed  => bag(4),
        },
        'a',
      ],
    ],
    "updates can be got",
  ) or diag explain($res);
}

subtest "invalid sinceState" => sub {
  subtest "too high" => sub {
    my $res = $ctx->process_request([
      [ getCookieUpdates => { sinceState => 999 }, 'a' ],
    ]);

    cmp_deeply(
      $res,
      [
        [
          error => superhashof({ type => 'invalidArguments' }),
          'a',
        ],
      ],
      "updates can't be got for invalid sinceState",
    ) or diag explain($res);
  };

  subtest "too low" => sub {
    my $res = $ctx->process_request([
      [ getCookieUpdates => { sinceState => 1 }, 'a' ],
    ]);

    cmp_deeply(
      $res,
      [
        [
          error => superhashof({ type => 'cannotCalculateChanges' }),
          'a',
        ],
      ],
      "updates can't be got for invalid sinceState",
    ) or diag explain($res);
  };
};

{
  my $get_res = $ctx->process_request([
    [ getCookies => { ids => [ 1, @created_ids ] }, 'a' ],
  ]);

  my $res = $ctx->process_request([
    [ getCookieUpdates => { sinceState => 8, fetchRecords => 1 }, 'a' ],
  ]);

  cmp_deeply(
    $res,
    [
      [
        cookieUpdates => {
          oldState => 8,
          newState => 9,
          hasMoreUpdates => bool(0),
          changed  => bag(1, @created_ids),
          removed  => bag(4),
        },
        'a',
      ],
      [
        cookies => {
          $get_res->[0][1]->%*,
          list => bag( $get_res->[0][1]{list}->@* ),
        },
        'a',
      ]
    ],
    "updates can be got (with implicit fetch)",
  ) or diag explain($res);
}

{
  my $res = $ctx->process_request([
    [
      setCakes => {
        ifInState => '0-0',
        create    => {
          yum => { type => 'wedding', layer_count => 4, recipeId => 1 }
        }
      },
      'cake!',
    ],
  ]);

  cmp_deeply(
    $res,
    [
      [
        cakesSet => superhashof({
          created => {
            yum => superhashof({ baked_at => ignore() }),
          }
        }),
        'cake!',
      ],
    ],
    "we can bake cakes",
  ) or diag explain($res);
}

{
  my $res = $ctx->process_request([
    [
      setCookies => {
        ifInState => 9,
        destroy   => [ 3 ],
        create    => { blue => {} },
        update    => { 2 => { delicious => 0 } },
      },
      'poirot'
    ],
  ]);

  cmp_deeply(
    $res,
    [
      [
        cookiesSet => superhashof({
          oldState => 9,
          newState => 9,

          notCreated   => { blue => ignore() },
          notUpdated   => { 2    => ignore() },
          notDestroyed => { 3    => ignore() },
        }),
        'poirot'
      ],
    ],
    "no state change when no destruction",
  ) or diag explain($res);

  my $state = $ctx->schema->resultset('State')->search({
    accountId => 1,
    type => 'cookies',
  })->first;

  is($state->highestModSeq, 9, "no updates, no state change");
}

done_testing;
