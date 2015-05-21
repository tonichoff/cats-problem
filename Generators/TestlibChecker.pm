package CATS::Formal::Generators::TestlibChecker;

use TestlibBase;
use parent -norequire, 'CATS::Formal::Generators::TestlibBase';

my $pe = '_constraint_result_';
sub generate_description {
    my ($self, $fd) = @_;
    if ($fd->{type} == CATS::Formal::Constants::FD_TYPES->{ROOT}) {
        my $input = $fd->find_child_by_type(CATS::Formal::Constants::FD_TYPES->{INPUT});
        foreach my $child (@{$input->{children}}){
            my $obj = $self->generate_obj($child, '', 1);
            $self->{input_reader} .= $obj->{reader};
            $self->{declarations} .= $obj->{declaration};
        }
        
        $self->{mode} = 'OUTPUT';
        my $output = $fd->find_child_by_type(CATS::Formal::Constants::FD_TYPES->{OUTPUT});
        my @output_compare = ();
        foreach my $child(@{$output->{children}}){
            my $obj = $self->generate_obj($child, '_output.', 1);
            $self->{output_reader} .= $obj->{reader};
            $self->{output_declarations} .= $obj->{declaration};
            push @output_compare, "f.$obj->{name} == s.$obj->{name}";
        }
        my $output_compare = join ' && ', @output_compare;
        $self->{output_compare} = $output_compare;
        $self->{mode} = undef;
        return;
    } else { die "not implemented" };
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
}

Output readOutput(InStream& $stream_name, TResult $pe){
    Output _output;
$self->{output_reader}
    return _output;
}

void _checkSolution(){
    _test_(_pa == _ja, _wa);
}

int main(int argc, char** argv){
    registerTestlibCmd(argc, argv);
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