package CATS::Problem::Tags;

use strict;
use warnings;

sub parse_tag_condition
{
    my ($cond, $on_error) = @_;
    $cond or return {};
    $on_error //= sub { die @_ };
    my $result = {};
    my $i = 0;
    for (split ',', $cond, -1) {
        $i++;
        my ($neg, $name, $value) = /^\s*(\!)?\s*([a-zA-Z][a-zA-Z0-9_]*)\s*(?:=\s*(\S+))?\s*$/;
        $name or return $on_error->("Incorrect condition format in part $i");
        $result->{$name} = [ $neg ? 1 : 0, $value ];
    }
    $result;
}

sub check_tag_condition
{
    my ($tags, $cond, $on_error) = @_;
    $on_error //= sub { die @_ };
    ref $tags eq 'HASH' && ref $cond eq 'HASH' or return $on_error->("tags and cond must be hashes");
    for (keys %$cond) {
        my ($tneg, $tvalue) = @{$tags->{$_} // [ 1, '' ]};
        $tneg && $tvalue and return $on_error->("Negated value for tag '$_'");
        my ($neg, $value) = @{$cond->{$_}};
        $neg ?
            (defined $value ? $value ne $tvalue : $tneg) :
            (defined $value ? $value eq $tvalue : !$tneg)
            or return 0;
    }
    1;
}

1;
