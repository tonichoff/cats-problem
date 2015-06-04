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

my $write_file_name_in_errors = 1;

sub enable_file_name_in_errors {
    $write_file_name_in_errors = 1;
}

sub disable_file_name_in_errors {
    $write_file_name_in_errors = 0;
}

my $file_name;
sub parse_descriptions {
    my ($is_files, %descriptions) = @_;
    my $parser = CATS::Formal::Parser->new();
    my $fd;
    my @keys = ('INPUT', 'ANSWER', 'OUTPUT'); 
    foreach my $namespace (@keys) {
        my $text = $descriptions{$namespace};
        $text || next;
        $file_name = 'unnamed';
        if ($is_files) {
            $file_name = $text;
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
        if ($write_file_name_in_errors) {
            $error .= " : $file_name";
        }
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

sub generate_source_from_texts {
    my ($gen_id, %descriptions) = @_;
    return generate_source($gen_id, 0, %descriptions);
}

sub generate_source_from_files {
    my ($gen_id, %files) = @_;
    return generate_source($gen_id, 1, %files);
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
    my ($out, $gen_id, %files) = @_;
    my $res = generate_source_from_files($gen_id, %files);
    write_res_to_file($res, $out);
    return $res;
}

sub validate {
    my ($d_is_files, $v_is_files, $descriptions, $to_validate) = @_;
    my $fd_root = parse_descriptions($d_is_files, %$descriptions);
    unless ($fd_root) {
        my $error = CATS::Formal::Error::get();
        if ($write_file_name_in_errors) {
            $error .= " : $file_name";
        }
        return $error;
    }
    eval {
        CATS::Formal::UniversalValidator->new()->validate($fd_root, $v_is_files, %$to_validate);
    };
    CATS::Formal::Error::propagate_bug_error();
    CATS::Formal::Error::get();
}

1;