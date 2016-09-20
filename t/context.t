use 5.20.0;
use warnings;
use utf8;
use experimental qw(lexical_subs signatures postderef refaliasing);

use lib 't/lib';

use Bakesale;
use Bakesale::App;
use Bakesale::Schema;
use Test::More;

my ($app, $jmap_tester) = Bakesale::Test->new_test_app_and_tester;

{
  # No user cookie, should get 401 response
  my $res = $jmap_tester->request([[ getCookies => {} ]])->http_response;
  is($res->code, 401, 'got 401 with no cookie');
  is($res->decoded_content, '', 'empty body');
}

{
  # Bad user cookie, should get 401 response with error
  $jmap_tester->_set_cookie('bakesaleUserId', "-5");

  my $res = $jmap_tester->request([[ getCookies => {} ]])->http_response;
  is($res->code, 401, 'got 401 with bad cookie');
  is($res->decoded_content, '{"error":"bad auth"}', 'got error in body');
}

done_testing;
