package CATS::Formal::Generators::XML;
use lib '..';
use Generators::BaseGenerator;
use parent -norequire, 'CATS::Formal::Generators::BaseGenerator';

sub generate {
    $_[1]->stringify;
}

1;