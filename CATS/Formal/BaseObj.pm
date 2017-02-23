package CATS::Formal::BaseObj;

use strict;
use warnings;

sub generate {
    $_[1]->generate($_[0]);
}

sub stringify {
    die "called abstract method CATS::Formal::BaseObj->stringify";
}

sub is_expr {0;}
sub is_description {0;}

1;
