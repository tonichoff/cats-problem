package CATS::Formal::Generators::BaseGenerator;
use strict;
use warnings;

sub new {
    my $class = shift;
    bless {@_}, $class;
}

sub generate {
    die "called abstract method BaseGenerator::generate";
}
1;