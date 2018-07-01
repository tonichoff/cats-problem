use strict;
use warnings;

use lib '..';

use Test::More;
use Test::Exception;

use CATS::Testset;

my $testsets = {
    t1 => { tests => '1,2,3' },
    t2 => { tests => 't1' },
    tr0 => { tests => 'tr0' },
    tr1 => { tests => 'tr2' },
    tr2 => { tests => 'tr1' },

    sc0 => { tests => '6,7', points => 0 },
    sc1 => { tests => '1-5', points => 10 },
    sc2 => { tests => '5-6', points => 20, depends_on => 't1,5' },
    scn => { tests => 'sc1,3', points => 7 },
    sc => { tests => 'sc1' },
    sca => { tests => 'sc,sc2' },

    tdr1 => { tests => '1', depends_on => 'tdr2' },
    tdr2 => { tests => '2', depends_on => 'tdr1' },
    tdr3 => { tests => '3', depends_on => 'tdr1,tdr2' },

    tdc1 => { tests => '4', depends_on => 't1' },
    tdc2 => { tests => '5', depends_on => 'tdc1,t1' },
    tdc3 => { tests => '6', depends_on => 'tdc2,t1' },
};

sub psr { CATS::Testset::parse_simple_rank($_[0], sub { die @_ }) }
sub ptr { CATS::Testset::parse_test_rank($testsets, $_[0], sub { die @_ }, include_deps => $_[1]) }
sub val { CATS::Testset::validate_testset($testsets, $_[1], $_[0], sub { die @_ }) }

sub hu { my %h; $h{$_} = undef for @_; \%h; }
sub h1 { my %h; $h{$_} = 1 for @_; \%h; }

plan tests => 6;

subtest 'simple', sub {
    plan tests => 15;

    is_deeply psr('1'), [ 1 ];
    is_deeply psr('1,3'), [ 1, 3 ];
    is_deeply psr('2-4'), [ 2 .. 4 ];
    is_deeply psr('05,003'), [ 3, 5 ], 'leading zero';
    is_deeply psr(' 1, 7 - 8, 3- 6,9 '), [ 1, 3 .. 9 ];
    is_deeply psr('1-10-2'), [ 1, 3, 5, 7, 9 ], 'step 2';
    is_deeply psr('1-13-3'), [ 1, 4, 7, 10, 13 ], 'step 3';

    throws_ok { psr('') } qr/empty/i;
    throws_ok { psr(',') } qr/empty/i;
    throws_ok { psr('?') } qr/bad/i;
    throws_ok { psr('2,1-3') } qr/duplicate.*2/i;
    throws_ok { psr('55-') } qr/bad/i;
    throws_ok { psr('1-2--3') } qr/bad/i;
    throws_ok { psr('1-2-0') } qr/step/i;
    throws_ok { psr('1-10000') } qr/many/i;
};

subtest 'basic', sub {
    plan tests => 11;

    is_deeply ptr('1'), hu(1);
    is_deeply ptr('1,3'), hu(1, 3);
    is_deeply ptr('2-4'), hu(2 .. 4);
    is_deeply ptr('05,003'), hu(3, 5), 'leading zero';
    is_deeply ptr(' 1, 7 - 8, 3 - 9 '), hu(1, 3 .. 9);
    is_deeply ptr('1-10-2'), hu(1, 3, 5, 7, 9), 'step 2';

    throws_ok { ptr('') } qr/empty/i;
    throws_ok { ptr(',') } qr/empty/i;
    throws_ok { ptr('?') } qr/bad/i;
    throws_ok { ptr('1-2--3') } qr/bad/i;
    throws_ok { ptr('1-2-0') } qr/step/i;
};

subtest 'testsets', sub {
    plan tests => 6;
    is_deeply(ptr('t1'), hu(1 .. 3));
    throws_ok { val('t1', h1(1, 3)) } qr/undefined test 2/i, 'undefined test';
    is_deeply(ptr('t2'), hu(1 .. 3));
    throws_ok { ptr('x') } qr/unknown testset/i;
    throws_ok { ptr('tr0') } qr/recursive/i, 'direct recursion';
    throws_ok { ptr('tr2') } qr/recursive/i, 'indirect recursion';
};

subtest 'scoring groups', sub {
    plan tests => 8;
    my %t0 = map { $_ => $testsets->{sc0} } 6, 7;
    is_deeply ptr('sc0'), \%t0, 'points 0';
    my %t1 = map { $_ => $testsets->{sc1} } 1..5;
    is_deeply ptr('sc1'), \%t1, 'points 10';
    is_deeply ptr('sc'), \%t1, 'points + depends';
    is_deeply ptr('sc, 9'), { %t1, 9 => undef };
    is_deeply ptr('sc1,sc0'), { %t0, %t1 }, 'sc0+1';
    throws_ok { ptr('scn') } qr/nested/i;
    throws_ok { ptr('sc1,sc2') } qr/ambiguous/i;
    throws_ok { ptr('sca') } qr/ambiguous/i;
};

sub is_keys { is_deeply [ sort keys %{$_[0]} ], $_[1], $_[2] }

subtest 'dependencies', sub {
    plan tests => 8;
    ok ptr('tdr1') && ptr('tdr2'), 'pre-check';
    throws_ok { val('tdr1', h1(1, 2)) } qr/contains and depends/i, 'circular 1';
    throws_ok { val('tdr2', h1(1, 2)) } qr/contains and depends/i, 'circular 1';
    ok val('tdr3', h1(1..3)), 'validate depends on circular';

    is_keys ptr('sc2', 1), [ 1..3, 5..6 ];
    is_keys ptr('tdc1', 1), [ 1..4 ];
    is_keys ptr('tdc3', 1), [ 1..6 ], 'diamond';
    ok val('tdc3', h1(1..6)), 'validate diamond';
};

sub pck { goto \&CATS::Testset::pack_rank_spec }

subtest 'pack', sub {
    plan tests => 7;
    is pck(), '', 'pack empty';
    is pck(33), '33', 'pack 33';
    is pck(1, 2, 3), '1-3', 'pack 1,2,3';
    is pck(4, 6, 8), '4-8-2', 'pack 4,6,8';
    is pck(5, 7, 4, 15..20), '4,5,7,15-20', 'pack 4-5,7,15-20';
    is pck(3, map $_ * 20, 1..10), '3,20-200-20', 'pack * 20';
    is pck(1, 2, 3, 7, 8, 9, 11, 15, 20, 25), '1-3,7-9,11,15-25-5', 'pack 3 ranges';
};
