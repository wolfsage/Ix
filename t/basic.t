use 5.20.0;
use warnings;
use experimental qw(signatures postderef);

use lib 't/lib';

use Bakesale;
use Bakesale::Schema;
use Test::Deep;
use Test::More;

sub test_schema {
  unlink 'test.sqlite';
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

my $Bakesale = Bakesale->new({ schema => test_schema() });

{
  my $res = $Bakesale->process_request([
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
  my $res = $Bakesale->process_request([
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
  my $res = $Bakesale->process_request([
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
  my $res = $Bakesale->process_request([
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

{
  my $res = $Bakesale->process_request([
    [
      setCookies => {
        ifInState => 8,
        create    => {
          yellow => { type => 'shortbread' },
          gold   => { type => 'aznac' },
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
        'a'
      ],
    ],
    "we can create cookies with setCookies",
  ) or diag explain($res);

  my @rows = $Bakesale->schema->resultset('Cookies')->search(
    { account_id => 1 },
    {
      order_by => 'id',
      result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    },
  );

  cmp_deeply(
    \@rows,
    [
      superhashof({ id => 1, type => 'half-eaten tim-tam' }),
      superhashof({ id => 2, type => 'oreo' }),
      superhashof({ id => 5, type => 'tim tam' }),
      superhashof({ id => 6, type => any(qw(shortbread aznac)) }),
      superhashof({ id => 7, type => any(qw(shortbread aznac)) }),
    ],
    "the db matches our expectations",
  ) or diag explain(\@rows);

  my $state = $Bakesale->schema->resultset('States')->search({
    account_id => 1,
    type => 'cookies',
  })->first;

  is($state->state, 9, "state ended got updated just once");
}

{
  my $res = $Bakesale->process_request([
    [
      setCakes => {
        ifInState => 1,
        create    => {
          yum => { type => 'wedding', layer_count => 4 }
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
  my $res = $Bakesale->process_request([
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

  my $state = $Bakesale->schema->resultset('States')->search({
    account_id => 1,
    type => 'cookies',
  })->first;

  is($state->state, 9, "no updates, no state change");
}

done_testing;
