use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 19;
use Test::Exception;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib $FindBin::Bin;

use CATS::Utils qw(
    date_to_iso
    date_to_rfc822
    external_url_function
    group_digits
    sanitize_file_name
);

{
is group_digits(''), '', 'group_digits empty';
is group_digits(1), '1', 'group_digits 1';
is group_digits(12), '12', 'group_digits 12';
is group_digits(123), '123', 'group_digits 123';
is group_digits(1234), '1 234', 'group_digits 1234';
is group_digits(12345), '12 345', 'group_digits 1234';
is group_digits(1234567890), '1 234 567 890', 'group_digits 1234567890';
is group_digits(10 ** 8), '100 000 000', 'group_digits 10^8';
is group_digits(234567890, '_'), '234_567_890', 'group_digits sep 234567890';
}

{
is date_to_iso('10.11.1991 12:33'), '19911110T123300', 'date_to_iso';
is date_to_iso(undef), undef, 'date_to_iso undef';
is date_to_rfc822('10.11.1991 12:33'), '10 Nov 1991 12:33 +1000', 'date_to_rfc822';
}

sub sfn { my $x = $_[0]; sanitize_file_name($x); $x; }
{
is sfn('a:\b.txt'), 'axxb.txt', 'sanitize_file_name 1';
is sfn('пример 1'), 'xxxxxxxxxxxxx1', 'sanitize_file_name 2';
}

{
is external_url_function('google.com', q => 'abc', a => 11), 'google.com?a=11&q=abc', 'url';
is external_url_function('t', qq => 'a?= %;&+1'), 't?qq=a%3F%3D%20%25%3B%26%2B1', 'url quoting';
}

{
    *h = *CATS::Utils::hex_dump;
    is h('A'), '41', 'hex_dump 1';
    is h('AB'), '41 42', 'hex_dump 2';
    is h('AB', 1), "41\n42", 'hex_dump line';
}
