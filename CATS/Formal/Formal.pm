package CATS::Formal::Formal;

use strict;
use warnings;

use File::Slurp;

use CATS::Formal::Parser;
use CATS::Formal::Error;
use CATS::Formal::UniversalValidator;

sub parse {
    my (%descriptions) = @_;
    my $parser = CATS::Formal::Parser->new();
    my $fd;
    my @keys = ('INPUT', 'ANSWER', 'OUTPUT');
    foreach my $namespace (@keys) {
        my $text = $descriptions{$namespace};
        defined $text || next;
        $fd = $parser->parse($text, $namespace, $fd);
        $fd || return $fd;
    }
    return $fd;
}

sub generate {
    my ($generator, %descriptions) = @_;
    my $fd_root = parse(%descriptions);
    return $fd_root && $generator->generate($fd_root);
}

sub validate {
    my ($descriptions, $validate, $skip_on_missed_data) = @_;
    my $fd_root = parse(%$descriptions) or return CATS::Formal::Error::get();;
    eval {
        CATS::Formal::UniversalValidator->new()->validate($fd_root, $validate, $skip_on_missed_data);
    };
    CATS::Formal::Error::propagate_bug_error();
    return CATS::Formal::Error::get();
}

sub check_syntax {
    if (parse(@_)) {
        return undef;
    }
    return CATS::Formal::Error::get();
}

1;
