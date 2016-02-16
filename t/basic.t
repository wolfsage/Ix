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

  my $cookieid = 1;
  $schema->resultset('Cookies')->populate([
    { accountid => 1, state => 1, id => $cookieid++, type => 'tim tam',
      baked_at => 1455319258 },
    { accountid => 1, state => 1, id => $cookieid++, type => 'oreo',
      baked_at => 1455319283 },
    { accountid => 2, state => 1, id => $cookieid++, type => 'thin mint',
      baked_at => 1455319308 },
    { accountid => 1, state => 3, id => $cookieid++, type => 'samoa',
      baked_at => 1455319240 },
    { accountid => 1, state => 8, id => $cookieid++, type => 'tim tam',
      baked_at => 1455310000 },
  ]);

  $schema->resultset('States')->populate([
    { accountid => 1, type => 'cookies', state => 8 },
    { accountid => 2, type => 'cookies', state => 1 },
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
          state => 10,
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
      },
      'a'
    ],
  ]);

  cmp_deeply(
    $res,
    [
      [
        cookiesSet => superhashof({
          created => {
            yellow => { id => ignore(), baked_at => ignore() },
            gold   => { id => ignore(), baked_at => ignore() },
          },
          notCreated => {
            blue   => superhashof({ type => 'invalidRecord' }),
          },
        }),
        'a'
      ],
    ],
    "we can create cookies with setCookies",
  ) or diag explain($res);
}

done_testing;
