package CATS::Formal::Error;

use strict;
use warnings;

my $error;

sub set {
    $error = $_[0];
    die $error;
}

sub clear {
    $error = undef;
}

sub get {
    return $error;
}

sub propagate_bug_error {
    die $@ if !get() && $@;
}

sub assert {
    my ($bool, $msg) = @_;
    if ($bool) {
        set($msg);
    }
}

1;
