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
use File::Spec;

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
    my ($name, $dir, $suffix) = fileparse($file, '.fd');
    CATS::Formal::Formal::generate_and_write(
        "$dir/$name.out", 'xml', 'INPUT' => $file 
    );
    my $res = compare_and_construct_status(
        $file, "$dir/$name", $idx, $cur_test, $tests_count, \&construct_status
    );
    update_counters($res->{status}, $res->{msg});
    print $res->{msg};
}

sub validator_test_run {
    my ($self) = @_;
    my ($file, $idx) = ($self->{file}, $self->{idx});
    my ($name, $dir, $suffix) = fileparse($file, '.fd');
    my $prepared  = $self->{prepare}->($dir, $name, $file, $idx)||return;
    my @ok_tests = <$dir$name.ok.*.in>;
    my @fail_tests = <$dir$name.fail.*.in>;
    my @tests = (@ok_tests, @fail_tests);
    my $local_tests_count = @tests;
    my $local_idx = 0;
    my @res = ();
    my $res = 'ok';
    foreach my $test_file (@tests){
        ++$local_idx;
        my $in_name = $dir . basename($test_file, '.in');
        $in_name =~ /.*(fail|ok)\.\d+$/;
        my $should_be_ok = $1 eq 'ok';
        my $output = $self->{test}->(
            $test_file, $prepared
        ) || '';
        my $s = $output && !$should_be_ok || !$output && $should_be_ok ?
           'ok' : 'fail';
        my $msg = construct_substatus($s, $idx, $local_idx, $local_tests_count, "$dir$in_name.in"),
        write_file("$in_name.out", $output);
        unlink "$in_name.out" if $clear;
        push @res, $msg;
        if ($s eq 'fail') {
            $res = 'fail';
        }
        update_counters($s, $msg, 'total');
    }
    
    my $msg = construct_status($res, $idx, $cur_test, $tests_count, $file) . join "", @res; 
    update_counters($res, $msg, 'main');
    $self->{clear}->($dir, $name);
    print $msg;
}

sub compile_testlib_validator {
    my ($dir, $name, $file, $idx) = @_;
    CATS::Formal::Formal::generate_and_write(
        "$dir$name.cpp", 'testlib_validator', 'INPUT' => $file  
    );
    my $compile = 
        "g++ -enable-auto-import -o $dir$name.exe $dir$name.cpp";
    print "compiling... $file\n";
    system($compile);
    if ($? >> 8) {
        my $msg = construct_status ("not compiled", $idx, $cur_test, $tests_count, $file);
        update_counters('not compiled', $msg, 'both');
        return ;
    }
    return "$dir$name.exe";
}

sub test_testlib_validator {
    my ($test_file, $executable) = @_;
    $executable = File::Spec->canonpath($executable);
    $test_file = File::Spec->canonpath($test_file);
    return `$executable < $test_file 2>&1`;
}

sub clear_testlib_validator {
    my ($dir, $name) = @_;
    unlink "$dir$name.exe" if $clear;
    unlink "$dir$name.cpp" if $clear;
}

sub prepare_universal_validator {
    my ($dir, $name, $file, $idx) = @_;
    return {
        INPUT => $file 
    };
};

sub test_universal_validator {
    my ($test_file, $from) = @_;
    return CATS::Formal::Formal::validate(1, 1, $from, {INPUT => $test_file});
}

sub clear_universal_validator {
    1;
}

sub get_parser_tests {
    my ($dir) = @_;
    my @files = <$dir/*.fd>;
    map new_test({file => $_, run => \&parser_test_run}) => @files;
}

sub get_validator_tests {
    my ($dir, $compile_func, $test_func, $clear_func) = @_;
    my @files = <$dir/*fd>;
    map new_test({
        file=> $_,
        run => \&validator_test_run,
        prepare => $compile_func,
        test => $test_func,
        clear => $clear_func,
    }) => @files;
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
    push @tests, get_validator_tests(
        'testlib_validator',
        \&compile_testlib_validator,
        \&test_testlib_validator,
        \&clear_testlib_validator
    );
    push @tests, get_validator_tests(
        'testlib_validator',
        \&prepare_universal_validator,
        \&test_universal_validator,
        \&clear_universal_validator
    );
    #push @tests, testlib_validator_tests;
} elsif ($group eq 'parser') {
    push @tests, get_parser_tests('parser');
} elsif ($group eq 'validator') {
    push @tests, get_validator_tests(
        'testlib_validator',
        \&compile_testlib_validator,
        \&test_testlib_validator,
        \&clear_testlib_validator
    );
} elsif ($group eq 'universal_validator'){
    push @tests, get_validator_tests(
        'testlib_validator',
        \&prepare_universal_validator,
        \&test_universal_validator,
        \&clear_universal_validator
    );
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
CATS::Formal::Formal::disable_file_name_in_errors();
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





