use strict;
use warnings;

use File::Basename qw(dirname);
use Cwd qw(abs_path);
my $curdir;
BEGIN {
    $curdir = dirname(abs_path($0));
}
use lib dirname(dirname(abs_path($0)));
use Formal;
use File::Compare;
use File::Slurp;
use File::Basename;
use Getopt::Long;

chdir($curdir);
my $total_count = 0;
my $cur_test = 0;
my $idx = 0;
my $first_error;
my $clear = 0;
my $passed_tests_count = 0;
my $failed_tests_count = 0;

sub write_status {
    my ($file, $basename, $idx) = @_;
    my $status = (compare("$basename.ans", "$basename.out") == 0) ? 'ok' : 'fail';
    my $res = sprintf "%-4s : %-4s : %-8s : %s\n", $status, $idx, "$cur_test/$total_count", $file;
    if ($status eq 'fail'){
        ++$failed_tests_count;
        if (!$first_error) {
            $first_error = {idx => $idx, msg => $res};
        }
    } else {
        ++$passed_tests_count;
    }
    unlink "$basename.out" if $clear;
    print $res;
}

sub new_test {
    my ($test) = @_;
    $test->{idx} = ++$idx;
    return $test;
}

sub parser_test_run {
    my ($self) = @_;
    my ($file, $idx) = ($self->{file}, $self->{idx});
    my $basename = basename($file, '.fd');
    CATS::Formal::Formal::generate_from_file_to_file($file, "./parser/$basename.out", 'xml', 1);
    write_status($file, "./parser/$basename", $idx);   
}

sub get_parser_tests {
    my ($dir) = @_;
    my @files = <$dir/*.fd>;
    map new_test({file => $_, run => \&parser_test_run}) => @files;
}

my $group = 'all';
my @tests = ();
my @indexes = ();
if ($group eq 'all') {
    push @tests, get_parser_tests('parser');
    #push @tests, testlib_checker_tests;
    #push @tests, testlib_validator_tests;
} elsif ($group eq 'parser') {
    push @tests, get_parser_tests('parser');
} else {
    die "unknown group";
}

if (@indexes) {
    my @tmp = ();
    foreach my $t (@tests) {
        foreach my $i (@indexes) {
            if ($t->{idx} == $i) {
                push @tmp, $t;
                last;
            }
        }
    }
    @tests = @tmp;
}
$total_count = @tests;

foreach (@tests){
    ++$cur_test;
    $_->{run}($_);
}

print "\n passed: $passed_tests_count";
print "\n failed: $failed_tests_count";
print "\n  total: $total_count";
if ($first_error) {
    print "\n\nfirst error:\n$first_error->{msg}";
}





