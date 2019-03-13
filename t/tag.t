use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 25;
use Test::Exception;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib $FindBin::Bin;

use CATS::Problem::Tags;

sub ptc { goto \&CATS::Problem::Tags::parse_tag_condition }

throws_ok { ptc('1'); } qr/part 1/, 'incorrect 1';
throws_ok { ptc('a,!'); } qr/part 2/, 'incorrect 2';
throws_ok { ptc(',,'); } qr/part 1/, 'empty part 1';

{
    my $err;
    ptc('1', sub { $err = $_[0] });
    like $err, qr/Incorrect/, 'on_error';
}

is_deeply ptc(undef), {}, 'parse undef';
is_deeply ptc(''), {}, 'parse empty';

{
    my $t = ptc('a,!b, c9=3,long_name = -5, !negeq=x');
    is keys %$t, 5, 'count';
    is_deeply $t->{a}, [ 0, undef ], 'tag a';
    is_deeply $t->{b}, [ 1, undef ], 'tag b';
    is_deeply $t->{c9}, [ 0, 3 ], 'tag c9';
    is_deeply $t->{long_name}, [ 0, -5 ], 'tag long_name';
    is_deeply $t->{negeq}, [ 1, 'x' ], 'tag negeq';

    my $chk = sub { CATS::Problem::Tags::check_tag_condition($t, ptc($_[0])) };
    ok $chk->('a'), 'check a';
    ok !$chk->('!a'), 'check !a';
    ok !$chk->('b'), 'check b';
    ok $chk->('!b'), 'check !b';
    ok $chk->('c9=3'), 'check c9';
    ok !$chk->('c9=4'), 'check c9 w';
    ok $chk->('!c9=4'), 'check c9 !w';
    ok !$chk->('nonexistent'), 'check nonexistent';
    ok !$chk->('nonexistent=5'), 'check nonexistent=5';
    ok $chk->('!nonexistent'), 'check !nonexistent';
    throws_ok { $chk->('negeq') } qr/negeq/, 'check negex';

    ok $chk->('a,!b,c9'), 'check and';
    ok !$chk->('a,!b,c9=1'), 'check !and';
}
