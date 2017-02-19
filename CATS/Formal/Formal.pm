package CATS::Formal::Formal;

use File::Slurp;

use Parser;
use Error;
use Generators::XML;
use Generators::TestlibChecker;
use Generators::TestlibValidator;
use Generators::TestlibStdChecker;
use UniversalValidator;

use constant GENERATORS => {
    'xml'                 => CATS::Formal::Generators::XML,
    'testlib_checker'     => CATS::Formal::Generators::TestlibChecker,
    'testlib_std_checker' => CATS::Formal::Generators::TestlibStdChecker,
    'testlib_validator'   => CATS::Formal::Generators::TestlibValidator,
};

sub set_all {
	my ($val) = @_;
	my $res = {};
	$res->{$_} = $val for qw(INPUT OUTPUT ANSWER);
	return $res;
}

sub parse_descriptions {
    my ($is_files, %descriptions) = @_;
    my $parser = CATS::Formal::Parser->new();
    my $fd;
    my @keys = ('INPUT', 'ANSWER', 'OUTPUT'); 
    foreach my $namespace (@keys) {
        my $text = $descriptions{$namespace};
        $text || next;
        if ($is_files->{$namespace} eq 'file') {
            $text = read_file($text);
        }        
        $fd = $parser->parse($text, $namespace, $fd);
        $fd || return $fd;
    }
    return $fd;
}

sub generate_source {
    my ($gen_id, $is_files, %descriptions) = @_;
    my $fd_root = parse_descriptions($is_files, %descriptions);
    unless ($fd_root) {
        my $error = CATS::Formal::Error::get();
        return {error => $error};
    }
    my $generator = GENERATORS->{$gen_id} ||
        return {error => "unknown generator $gen_id"};
    my $res = $generator->new()->generate($fd_root);
    unless ($res) {
        return {error => CATS::Formal::Error::get()};
    }
    return {ok => $res};
}

sub generate_source_from_files {
    my ($gen_id, %files) = @_;
    return generate_source($gen_id, default_v, %files);
}

sub write_res_to_file {
    my ($res, $out) = @_;
    if ($res->{error}) {
        write_file($out, $res->{error});
    } else {
        write_file($out, $res->{ok});
    }
}

sub generate_and_write {
    my ($files, $gen_id, $out) = @_;
    my $res = generate_source_from_files($gen_id, %$files);
    write_res_to_file($res, $out);
    return $res->{error};
}

sub part_copy {
    my ($h1, $h2, $keys1, $keys2) = @_;
    @{$h2->{@$keys2}} = @{$h1->{@$keys1}};
}

sub validate {
    my ($descriptions, $validate, $opt) = @_;
    $opt ||= {};
    my $fd_is = set_all($opt->{fd} || $opt->{all} || 'file');
    part_copy($opt, $fd_is, ['input_fd', 'output_fd', 'answer_fd'], ['INPUT', 'OUTPUT', 'ANSWER']);
    my $fd_root = parse_descriptions($fd_is, %$descriptions);
    unless ($fd_root) {
        my $error = CATS::Formal::Error::get();
        return $error;
    }
    my $data_is = set_all($opt->{data} || $opt->{all} || 'file');
    part_copy($opt, $data_is, ['input_data', 'output_data', 'answer_data'], ['INPUT', 'OUTPUT', 'ANSWER']);
    eval {
        CATS::Formal::UniversalValidator->new()->validate($fd_root, $data_is, %$validate);
    };
    CATS::Formal::Error::propagate_bug_error();
    CATS::Formal::Error::get();
}

sub generate {
    my ($fds, $gen_id, $out, $opt) = @_;
    $opt ||= {};
    $out ||= \*STDOUT;
    my $fd_is = set_all($opt->{fd} || $opt->{all} || 'file');
    part_copy($opt, $fd_is, ['input_fd', 'output_fd', 'answer_fd'], ['INPUT', 'OUTPUT', 'ANSWER']);
    my $res = generate_source($gen_id, $fd_is, %$fds);
    unless ($res->{error}) {
        write_res_to_file($res, $out);
    }
    return $res->{error};
}

1;