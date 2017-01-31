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
    tdc1 => { tests => '4', depends_on => 't1' },
    tdc2 => { tests => '5', depends_on => 'tdc1,t1' },
    tdc3 => { tests => '6', depends_on => 'tdc2,t1' },
};

sub ptr { CATS::Testset::parse_test_rank($testsets, $_[0], sub { die @_ }, include_deps => $_[1]) }

sub h { my %h; @h{@_} = undef; \%h; }

plan tests => 4;

subtest 'basic', sub {
    plan tests => 7;
    is_deeply(ptr('1'), h(1));
    is_deeply(ptr('1,3'), h(1, 3));
    is_deeply(ptr('2-4'), h(2 .. 4));
    is_deeply(ptr(' 1, 7 - 8, 3 - 9 '), h(1, 3 .. 9));

    throws_ok { ptr('') } qr/empty/i;
    throws_ok { ptr(',') } qr/empty/i;
    throws_ok { ptr('?') } qr/bad/i;
};

subtest 'testsets', sub {
    plan tests => 5;
    is_deeply(ptr('t1'), h(1 .. 3));
    is_deeply(ptr('t2'), h(1 .. 3));
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

subtest 'dependencies', sub {
    plan tests => 6;
    ok ptr('tdr1') && ptr('tdr2');
    throws_ok { ptr('tdr1', 1) } qr/recursive/i;
    throws_ok { ptr('tdr2', 1) } qr/recursive/i;
    is_deeply [ sort keys %{ptr('sc2', 1)} ], [ 1..3, 5..6 ];
    is_deeply [ sort keys %{ptr('tdc1', 1)} ], [ 1..4 ];
    throws_ok { ptr('tdc3', 1) } qr/recursive/i; # TODO: Remove this limitation.
};
