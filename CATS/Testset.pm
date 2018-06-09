package CATS::Testset;

use strict;
use warnings;

sub is_scoring_group { defined $_[0]->{points} || $_[0]->{hide_details} || defined $_[0]->{depends_on} }

sub parse_simple_rank {
    my ($rank_spec, $on_error) = @_;
    $on_error //= sub {};
    my %result;
    $rank_spec =~ s/\s+//g;
    for (split ',', $rank_spec) {
        /^(\d+)(?:-(\d+))?$/ or return $on_error->("Bad element '$_'");
        my ($from, $to) = ($1, $2 || $1);
        $from <= $to or return $on_error->("from > to");
        for my $t ($from .. $to) {
            $result{$t} and return $on_error->("Duplicate item $t");
            $result{$t} = 1;
        }
    }
    %result or return $on_error->('Empty rank specifier');
    [ sort keys %result ];
}

sub parse_test_rank {
    my ($all_testsets, $rank_spec, $on_error, %p) = @_;
    my (%result, %used, $rec);
    $rec = sub {
        my ($r, $scoring_group) = @_;
        $r =~ s/\s+//g;
        # Rank specifier is a comma-separated list, each element being one of:
        # * test number,
        # * range of test numbers,
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
            elsif (/^(\d+)(?:-(\d+))?$/) {
                my ($from, $to) = ($1, $2 || $1);
                $from <= $to or die \"from > to";
                for my $t ($from .. $to) {
                    die \"Ambiguous scoring group for test $t"
                        if $scoring_group && $result{$t} && $result{$t} ne $scoring_group;
                    $result{$t} = $scoring_group;
                    ++$scoring_group->{test_count} if $scoring_group;
                }
            }
            else {
                die \"Bad element '$_'";
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
    my (@ranks) = sort { $a <=> $b } @_;
    my (@ranges);
    my $range = [0, -1];
    for (@ranks, 0) {
        if ($range->[1] + 1 != $_) {
            push @ranges, "$range->[0]" . ($range->[0] == $range->[1] ? '' : "-$range->[1]")
                if $range->[0];
            $range->[0] = $_;
        }
        $range->[1] = $_;
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
