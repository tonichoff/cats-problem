package CATS::Formal::Formal;

use File::Slurp;

use Parser;
use Error;
use Generators::XML;
use Generators::TestlibChecker;
use Generators::TestlibValidator;

use constant GENERATORS => {
    'xml'               => CATS::Formal::Generators::XML,
    'testlib_checker'   => CATS::Formal::Generators::TestlibChecker,
    'testlib_validator' => CATS::Formal::Generators::TestlibValidator,
};

sub generate_source {
    my ($description_text, $generator_id) = @_;
    my $parser = CATS::Formal::Parser->new();
    my $fd_root = $parser->parse($description_text);
    $fd_root || return {error => CATS::Formal::Error::get()};
    my $generator = GENERATORS->{$generator_id} ||
        return {error => "unknown generator $generator_id"};
    return {ok => $generator->new()->generate($fd_root)};
}

sub generate_from_file {
    my ($file_name, $generator_id) = @_;
    my $text = read_file($file_name);
    my $res = generate_source($text, $generator_id);
    if ($res->{error} eq "empty file") {
        $res->{error} .= " '$file_name'";
    }
    return $res;
}

sub generate_from_file_to_file {
    my ($in, $out, $gen_id, $write_error) = @_;
    my $res = generate_from_file($in, $gen_id);
    return $res if $res->{error} && !$write_error;
    if ($res->{error}) {
        write_file($out, $res->{error});
    } else {
        write_file($out, $res->{ok});
    }
    return $res;
}



1;