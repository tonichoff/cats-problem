package CATS::Formal::Generators::XML;

use parent 'CATS::Formal::Generators::BaseGenerator';

sub generate {
    $_[1]->stringify;
}

1;