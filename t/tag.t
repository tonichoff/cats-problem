use strict;
use warnings;

use FindBin;
use Test::More tests => 21;
use Test::Exception;

use lib '..';
use lib $FindBin::Bin;

use ParserMockup;

my $p = ParserMockup::make({});

throws_ok { $p->parse_tag_condition('1'); } qr/part 1/, 'Incorrect 1';
throws_ok { $p->parse_tag_condition('a,!'); } qr/part 2/, 'Incorrect 2';

{
    my $t = $p->parse_tag_condition('a,!b, c9=3,long_name = -5, !negeq=x');
    is keys %$t, 5, 'count';
    is_deeply $t->{a}, [ 0, undef ], 'tag a';
    is_deeply $t->{b}, [ 1, undef ], 'tag b';
    is_deeply $t->{c9}, [ 0, 3 ], 'tag c9';
    is_deeply $t->{long_name}, [ 0, -5 ], 'tag long_name';
    is_deeply $t->{negeq}, [ 1, 'x' ], 'tag negeq';

    my $chk = sub { $p->check_tag_condition($t, $p->parse_tag_condition($_[0])) };
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
