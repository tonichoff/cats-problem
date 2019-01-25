package CATS::Testset;

use strict;
use warnings;

sub is_scoring_group { defined $_[0]->{points} || $_[0]->{hide_details} || defined $_[0]->{depends_on} }

my $range_re = qr/^(\d+)(?:-(\d+))?(?:-(\d+))?$/;

sub parse_range {
    my ($range_spec, $on_error) = @_;
    $range_spec =~ /$range_re/ or return $on_error->("Bad element '$_'");
    my ($from, $to, $step) = ($1, $2 || $1, $3 // 1);
    $from <= $to or return $on_error->('from > to');
    $step or return $on_error->('Zero step');
    my $count = int(($to - $from) / $step) + 1;
    $count < 10000 or return $on_error->('Too many tests');
    [ map $from + $_ * $step, 0 .. $count - 1 ];
}

sub parse_simple_rank {
    my ($rank_spec, $on_error) = @_;
    $on_error //= sub {};
    my %result;
    $rank_spec =~ s/\s+//g;
    for (split ',', $rank_spec) {
        my $range = parse_range($_, $on_error) or return;
        for my $t (@$range) {
            $result{$t} and return $on_error->("Duplicate item $t");
            $result{$t} = 1;
        }
    }
    %result or return $on_error->('Empty rank specifier');
    [ sort { $a <=> $b } keys %result ];
}

sub die_ref { die \$_[0] }

sub parse_test_rank {
    my ($all_testsets, $rank_spec, $on_error, %p) = @_;
    my (%result, %used, $rec);
    $rec = sub {
        my ($r, $scoring_group) = @_;
        $r =~ s/\s+//g;
        # Rank specifier is a comma-separated list, each element being one of:
        # * test number,
        # * range of test numbers with optional step,
        # * testset name.
        for (split ',', $r) {
            if (/^[a-zA-Z][a-zA-Z0-9_]*$/) {
                my $testset = $all_testsets->{$_} or die \"Unknown testset '$_'";
                $used{$_}++ and $p{include_deps} ? return : die \"Recursive usage of testset '$_'";
                my $sg = $scoring_group;
                if (is_scoring_group($testset)) {
                    die \"Nested scoring group '$_'" if $sg;
                    $sg = $testset;
                    $sg->{test_count} = 0;
                }
                $rec->($testset->{tests}, $sg);
                $rec->($testset->{depends_on}) if $p{include_deps} && $testset->{depends_on};
            }
            else {
                my $range = parse_range($_, \&die_ref) or return;
                for my $t (@$range) {
                    die \"Ambiguous scoring group for test $t"
                        if $scoring_group && $result{$t} && $result{$t} ne $scoring_group;
                    $result{$t} = $scoring_group;
                    ++$scoring_group->{test_count} if $scoring_group;
                }
            }
        }
    };
    eval { $rec->($rank_spec); %result or die \'Empty rank specifier'; }
        or $on_error && $on_error->(ref $@ ? "${$@} in rank spec '$rank_spec'" : $@);
    \%result;
}

sub validate_testset {
    my ($all_testsets, $all_tests, $testset_name, $on_error) = @_;
    my $testset = $all_testsets->{$testset_name};
    my $tests = parse_test_rank($all_testsets, $testset->{tests}, $on_error);
    for (keys %$tests) {
        $all_tests->{$_} or return $on_error->("Undefined test $_ in testset '$testset_name'");
    }
    if (my $dep = $testset->{depends_on}) {
        my $dep_tests = parse_test_rank($all_testsets, $dep, $on_error, include_deps => 1);
        # May be caused by circular references of individual tests, as opposed to recursive testsets.
        for (sort keys %$dep_tests) {
            return $on_error->("Testset '$testset_name' both contains and depends on test $_")
                if exists $tests->{$_};
        }
    }
    1;
}

sub pack_rank_spec {
    my ($prev, @ranks) = sort { $a <=> $b } @_ or return '';
    @ranks or return "$prev";
    my @ranges;
    my ($state, $from, $to, $step) = (2);
    for (@ranks, 0, -1) {
        if ($state == 2) {
            $step = $_ - $prev;
            $state = 3;
        }
        elsif ($state == 3) {
            if ($prev + $step == $_) {
                ($state, $from, $to) = (4, $prev - $step, $_);
            }
            else {
                push @ranges, $prev - $step;
                $step = $_ - $prev;
            }
        }
        elsif ($state == 4) {
            if ($prev + $step == $_) {
                $to = $_;
            }
            else {
                push @ranges, "$from-$to" . ($step > 1 ? "-$step" : '');
                $state = 2;
            }
        }
        $prev = $_;
    }
    join ',', @ranges;
}

sub get_all_testsets {
    my ($dbh, $pid) = @_;
    $dbh->selectall_hashref(qq~
        SELECT id, name, tests, points, comment, hide_details, depends_on
        FROM testsets WHERE problem_id = ?~,
        'name', undef,
        $pid) || {};
}

sub get_testset {
    my ($dbh, $table, $id, $update) = @_;

    my ($pid, $orig_testsets, $testsets) = $dbh->selectrow_array(qq~
        SELECT T.problem_id, T.testsets, COALESCE(T.testsets, CP.testsets)
        FROM $table T
        INNER JOIN contest_problems CP ON
            CP.contest_id = T.contest_id AND CP.problem_id = T.problem_id
        WHERE T.id = ?~, undef,
        $id);

    my @all_tests = @{$dbh->selectcol_arrayref(qq~
        SELECT rank FROM tests WHERE problem_id = ? ORDER BY rank~, undef,
        $pid
    )};
    $testsets or return map { $_ => undef } @all_tests;

    if ($update && ($orig_testsets || '') ne $testsets) {
        $dbh->do(qq~
            UPDATE $table SET testsets = ? WHERE id = ?~, undef,
            $testsets, $id);
        $dbh->commit;
    }

    my %tests = %{parse_test_rank(get_all_testsets($dbh, $pid), $testsets, sub { warn @_ })};
    map { exists $tests{$_} ? ($_ => $tests{$_}) : () } @all_tests;
}

1;
