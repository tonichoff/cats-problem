package CATS::Formal::Generators::TestlibChecker;

use TestlibBase;
use parent -norequire, 'CATS::Formal::Generators::TestlibBase';

my $pe = '_constraint_result_';
sub generate_description {
    my ($self, $fd) = @_;
    die "expect ROOT object" if $fd->{type} != CATS::Formal::Constants::FD_TYPES->{ROOT};
    my $input = $fd->find_child_by_type(CATS::Formal::Constants::FD_TYPES->{INPUT});
    $self->{params} = $input->{attributes};
    my @input_objects = map $self->generate_obj($_, '', 1) => @{$input->{children}};
    foreach my $obj (@input_objects){
        $self->{input_reader} .= $obj->{reader};
        next if $obj->{newline_obj};
        if ($self->{params}->{strict} && $obj->{space_reader} && $obj != $input_objects[-1]) {
            $self->{input_reader} .= $self->generate_readSpace("    ");
        }
        $self->{declarations} .= $obj->{declaration};
    }
    
    $self->{mode} = 'OUTPUT';
    my $output = $fd->find_child_by_type(CATS::Formal::Constants::FD_TYPES->{OUTPUT});
    my @output_compare = ();
    $self->{params} = $output->{attributes};
    my @output_objects = map $self->generate_obj($_, '_output.', 1)
        => @{$output->{children}};
    foreach my $obj (@output_objects){
        $self->{output_reader} .= $obj->{reader};
        next if $obj->{newline_obj};
        if ($self->{params}->{strict} && $obj->{space_reader} && $obj != $output_objects[-1]) {
            $self->{output_reader} .= $self->generate_readSpace("    ");
        }
        $self->{output_declarations} .= "    $obj->{declaration}";
        push @output_compare, "f.$obj->{name} == s.$obj->{name}";
    }
    my $output_compare = join ' && ', @output_compare;
    $self->{output_compare} = $output_compare;
    $self->{mode} = undef;
    $self->{input_strict}  = $input->{attributes}->{strict};
    $self->{output_strict} = $output->{attributes}->{strict};
}

sub constraint_function {
    my ($self, $constraint_code) = @_;
    if ($self->{mode} ne 'OUTPUT') {
        return $self->SUPER::constraint_function($constraint_code);
    }
    return "_test_($constraint_code, $pe)";
}

sub pattern {
    my $self = shift;
    my $stream_name = $self->{stream_name};
    my $output_compare = $self->{output_compare};
    my $in_strict = $self->{input_strict};
    my $out_strict = $self->{output_strict};
    my $input_seekeof = $in_strict ? '' : "$stream_name.seekEof();";
    my $output_seekeof = $out_strict ? '' : "$stream_name.seekEof();";
    my $input_strict = $in_strict ? 'true' : 'false';
    my $output_strict = $out_strict ? 'true' : 'false';
    return <<"END"
#include "testlib.h"
#define _test_(C, R) if (!(C)) quitf(R, "Condition failed: \"" #C "\" at line:%d", __LINE__)

using namespace std;

$self->{type_declarations}struct Output;
typedef Output Answer;

$self->{declarations}
$self->{type_definitions}struct Output {
$self->{output_declarations}
};
bool operator==(const Output& f, const Output& s){
    return $output_compare;
}

Output _pa;
Answer _ja;

$self->{functions}

void readInput(InStream& $stream_name){
$self->{input_reader}
    $input_seekeof
    $stream_name.readEof();
}

Output readOutput(InStream& $stream_name, TResult $pe){
    Output _output;
$self->{output_reader}
    $output_seekeof
    $stream_name.readEof();
    return _output;
}

void _checkSolution(){
    _test_(_pa == _ja, _wa);
}

int main(int argc, char** argv){
    registerTestlibCmd(argc, argv);
    inf.strict = $input_strict;
    ouf.strict = $output_strict;
    ans.strict = $output_strict;
    /* comment out, if input not needed */
    readInput(inf);
    _pa = readOutput(ouf, _wa);
    _ja = readOutput(ans, _fail);
    _checkSolution();
    
    quit(_ok, "all ok");
}
END
}

1;