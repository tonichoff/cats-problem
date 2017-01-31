use strict;
use warnings;

use FindBin;
use Test::More tests => 8;
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
}
