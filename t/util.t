use 5.20.0;
use warnings;
use utf8;
use experimental qw(lexical_subs signatures postderef);

use Test::More;

use Ix::Util qw(splitquoted);

{
  my $input = q{"foo \" bar" baz 'bingo' 'bi"n\g' "boo};
  my @result = splitquoted($input);

  is_deeply(
    \@result,
    [  'foo " bar', 'baz', 'bingo', 'bi"ng', '"boo' ],
    "we split up quoted strings as expected",
  );
}

{
  my $input = q{    };
  my @result = splitquoted($input);

  is_deeply(
    \@result,
    [],
    "all-spaces string becomes () and not (undef)",
  );
}

done_testing;
