use strict;
use warnings;

use FindBin;
use Test::More tests => 13;
use Test::Exception;

use lib '..';
use lib $FindBin::Bin;

use CATS::Constants;
use CATS::DevEnv;

{
    my $de = CATS::DevEnv->new({
        version => 1,
        des => [
            { code => 5  , id => 90183, file_ext => 'cpp' },
            { code => 104, id => 29384, file_ext => 'pp;pas;dpr' },
        ],
    });

    is $de->by_file_extension('f.cpp')->{code}, 5, 'by_file_extension cpp';
    is $de->by_file_extension('f.pas')->{code}, 104, 'by_file_extension pas';
    is $de->by_file_extension('f.z'), undef, 'by_file_extension z';

    is $de->by_code(104)->{id}, 29384, 'by_code';
    is $de->by_id(90183)->{code}, 5, 'by_id';

    ok $de->is_good_version(1), 'good version';
    ok !$de->is_good_version(2), 'bad version';
}

{
    my $de = CATS::DevEnv->new({
        version => 2,
        des => [
            map { code => 100 - $_, id => 1000 + $_ }, 1..80
        ],
    });

    use bigint;

    is scalar @{$de->des}, 80, 'count';
    is $cats::de_req_bitfield_size, 62, 'bitfield_size'; # Hardcoded into following tests.
    is 1 << 62, 2 ** 62, '64-bit shift';
    is_deeply [ $de->bitmap_by_codes(20, 25) ], [ 33, 0 ], 'bitmap_by_codes';
    # Avoid warning on non-portable 64-bit hexes, still works due to bigint.
    is_deeply [ $de->bitmap_by_codes(20..99) ], [ 0 + '0x3fff_ffff_ffff_ffff', 0x3_ffff ], 'bitmap_by_codes all';
    is_deeply [ $de->bitmap_by_ids(1080, 1019, 1018, 1001) ], [ 0 + '0x2000_0000_0000_0001', 0x2_0001 ], 'bitmap_by_ids';
}
