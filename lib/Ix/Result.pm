use 5.20.0;
package Ix::Result;
use Moose::Role;
use experimental qw(signatures postderef);

use namespace::autoclean;

requires 'result_type';
requires 'result_properties';

1;
