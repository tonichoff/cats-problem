package CATS::Formal::Generators::XML;

use strict;
use warnings;

use parent 'CATS::Formal::Generators::BaseGenerator';

sub generate {
    $_[1]->stringify;
}

sub id {
    'xml';
}

1;
