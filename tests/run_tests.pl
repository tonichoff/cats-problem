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
my $tests_count = 0;
my $cur_test = 0;
my $idx = 0;
my $first_error;
my $clear = 1;
my $passed_tests_count = 0;
my $failed_tests_count = 0;

my $total_count = 0;
my $total_passed = 0;
my $total_failed = 0;

sub compare_and_construct_status {
    my ($file, $basename, $idx, $cur_test, $total_count, $construct_status) = @_;
    my $status = (compare("$basename.ans", "$basename.out") == 0) ? 'ok' : 'fail';
    my $res = $construct_status->($status, $idx, $cur_test, $total_count, $file);
    unlink "$basename.out" if $clear;
    {status=> $status, msg => $res};
}

sub update_counters {
    my ($status, $msg, $type) = @_;
    $type ||= 'both';
    my $both = $type eq 'both';
    my $total = $both || $type eq 'total';
    my $main = $both || $type eq 'main';
    ++$total_count if $total;
    if ($status eq 'fail'){
        ++$total_failed if $total;
        ++$failed_tests_count if $main;
        if (!$first_error && ($main)) {
            $first_error = $msg;
        }
    } else {
        ++$total_passed if $total;
        ++$passed_tests_count if $main;
    }
}

sub construct_status {
    my ($status, $idx, $cur, $total, $file) = @_;
    my $msg = sprintf "%-12s : %-4s : %-8s : %s\n",
         $status, $idx, "$cur/$total", $file;
    $msg;
}

sub construct_substatus {
    my ($status, $idx, $cur, $total, $file) = @_;
    my $msg = sprintf "    %-8s : %-4s : %-8s : %s\n",
         $status, $idx, "$cur/$total", $file;
    $msg; 
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
    my $res = compare_and_construct_status(
        $file, "./parser/$basename", $idx, $cur_test, $tests_count, \&construct_status
    );
    update_counters($res->{status}, $res->{msg});
    print $res->{msg};
}

sub validator_test_run {
    my ($self) = @_;
    my ($file, $idx) = ($self->{file}, $self->{idx});
    my $basename = basename($file, '.fd');
    CATS::Formal::Formal::generate_from_file_to_file(
        $file, "./testlib_validator/$basename.cpp", 'testlib_validator', 1
    );
    my $compile = 
        "g++ -enable-auto-import -o ./testlib_validator/$basename.exe ./testlib_validator/$basename.cpp";
    print "compiling... $file\n";
    system($compile);
    if ($? >> 8) {
        my $msg = construct_status ("not compiled", $idx, $cur_test, $tests_count, $file);
        update_counters('not compiled', $msg, 'both');
        return;
    }
    
    my @ok_tests = <./testlib_validator/$basename.ok.*.in>;
    my @fail_tests = <./testlib_validator/$basename.fail.*.in>;
    my @tests = (@ok_tests, @fail_tests);
    my $tests = @tests;
    my $local_idx = 0;
    my @res = ();
    my $res = 'ok';
    foreach my $t (@tests){
        ++$local_idx;
        my $b = basename($t, '.in');
        my ($name, $path, $suffix) = fileparse($t, qw(.in));
        $name =~ /.*(fail|ok)\.\d+$/;
        my $should_be_ok = $1 eq 'ok';
        chdir 'testlib_validator';
        my $output = `$basename.exe < $name.in 2>&1`;
        chdir '..';
        my $s = $output && !$should_be_ok || !$output && $should_be_ok ?
               'ok' : 'fail';
        my $local_res = {
            status => $s,
            msg => construct_substatus($s, $idx, $local_idx, $tests, "./testlib_validator/$b.in")
        };
        
        write_file("./testlib_validator/$b.out", $output);
        unlink "./testlib_validator/$b.out" if $clear;
        #my $local_res = compare_and_construct_status(
        #    "./testlib_validator/$b.in", "./testlib_validator/$b", $idx, $local_idx, $tests, \&construct_substatus
        #);
        push @res, $local_res->{msg};
        if ($local_res->{status} eq 'fail') {
            $res = 'fail';
        }
        update_counters($local_res->{status}, $local_res->{msg}, 'total');
    }
    
    my $msg = construct_status($res, $idx, $cur_test, $tests_count, $file) . join "", @res; 
    update_counters($res, $msg, 'main');
    unlink "./testlib_validator/$basename.exe" if $clear;
    unlink "./testlib_validator/$basename.cpp" if $clear;
    print $msg;
}

sub get_parser_tests {
    my ($dir) = @_;
    my @files = <$dir/*.fd>;
    map new_test({file => $_, run => \&parser_test_run}) => @files;
}

sub get_validator_tests {
    my ($dir) = @_;
    my @files = <$dir/*fd>;
    map new_test({file=> $_, run => \&validator_test_run}) => @files;
}

my $group = 'all';
my @tests = ();
my @indexes = ();

sub uniq {
    my %seen;
    return grep { !$seen{$_}++ } @_;
}

if ($group eq 'all') {
    push @tests, get_parser_tests('parser');
    push @tests, get_validator_tests('testlib_validator');
    #push @tests, testlib_validator_tests;
} elsif ($group eq 'parser') {
    push @tests, get_parser_tests('parser');
} elsif ($group eq 'validator') {
    push @tests, get_validator_tests('testlib_validator');
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
$tests_count = @tests;

foreach (@tests){
    ++$cur_test;
    $_->{run}($_);
}

printf "\n passed: %4s %-12s: $total_passed", $passed_tests_count, 'total_passed';
printf "\n failed: %4s %-12s: $total_failed", $failed_tests_count, 'total_failed';
printf "\n tests : %4s %-12s: $total_count",  $tests_count,        'total_count';
if ($first_error) {
    print "\n\nfirst error:\n$first_error";
}





