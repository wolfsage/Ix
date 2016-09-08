use strict;
use warnings;
package Test::Deep::JSON;

use Test::Deep ();

use Exporter 'import';
our @EXPORT = qw( jcmp_deeply jstr jnum jbool jtrue jfalse );

sub jcmp_deeply {
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  local $Test::Deep::LeafWrapper = \&Test::Deep::str;
  Test::Deep::cmp_deeply(@_);
}

sub jstr  { Test::Deep::all( Test::Deep::obj_isa('JSON::Typist::String'),
                             Test::Deep::str($_[0])) }

sub jnum  { Test::Deep::all( Test::Deep::obj_isa('JSON::Typist::Number'),
                             Test::Deep::num($_[0])) }

sub jbool {
  Test::Deep::all(
    Test::Deep::any(
      Test::Deep::obj_isa('JSON::XS::Boolean'),
      Test::Deep::obj_isa('JSON::PP::Boolean'),
    ),
    (@_ ? bool(@_) : ()),
  );
}

sub jtrue  { jbool(1) }
sub jfalse { jbool(0) }

1;
