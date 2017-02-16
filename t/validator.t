use 5.20.0;
use warnings;
use utf8;
use experimental qw(lexical_subs signatures postderef refaliasing);

use lib 't/lib';

use Ix::Validators qw(domain email idstr);
use Test::More;
use Ix::Util qw(ix_new_id);

my $iderr = idstr();
for my $input (ix_new_id(), ix_new_id()) {
  ok( ! $iderr->($input), "$input is a valid idstr");
}

for my $input (qw( -0 +0 +1 banana ab-cd-ef), uc ix_new_id()) {
  ok( $iderr->($input), "$input is not a valid idstr");
}

subtest "domain validator" => sub {
  my $domerr = domain();

  my @domains = qw( xyz.com  your-face.com pobox.co.nz );
  ok(! $domerr->($_), "$_ is a valid domain") for @domains;

  my @bogus = ('not a domain', qw(not-a-domain www.example.com.));
  ok(  $domerr->($_), "$_ is not a valid domain") for @bogus;
};

subtest "email validator" => sub {
  my $emailerr = email();
  ok( $emailerr->('yourface@myface.ix.'), "trailing dots no good in email");
};

done_testing;
