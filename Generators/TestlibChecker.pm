package CATS::Formal::Generators::TestlibChecker;

use TestlibBase;
use parent -norequire, 'CATS::Formal::Generators::TestlibBase';

sub generate_description {
    my ($self, $fd) = @_;
    if ($fd->{type} == CATS::Formal::Constants::FD_TYPES->{ROOT}) {
        my $input = $fd->find_child_by_type(CATS::Formal::Constants::FD_TYPES->{INPUT});
        foreach my $child (@{$input->{children}}){
            my $obj = $self->generate_obj($child, '', 1);
            $self->{input_reader} .= $obj->{reader};
            $self->{declarations} .= $obj->{declaration};
        }
        
        my $output = $fd->find_child_by_type(CATS::Formal::Constants::FD_TYPES->{OUTPUT});
        foreach my $child(@{$output->{children}}){
            my $obj = $self->generate_obj($child, '', 1);
            $self->{output_reader} .= $obj->{reader};
            $self->{declarations} .= $obj->{declaration};
        }
        return;
    } else { die "not implemented" };
}

sub pattern {
    my $self = shift;
    my $stream_name = $self->{stream_name};
    return <<"END"
#include "testlib.h"

using namespace std;

$self->{type_declarations}
$self->{declarations}
$self->{type_definitions}
$self->{functions}

void readInput(InStream& $stream_name){
$self->{input_reader}
}

void readOutput(InStream& $stream_name){
$self->{output_reader}
}

void readAns(InStream& $stream_name){
$self->{ans_reader}
}

void _checkSolution(){
    /*write ckecker here*/
}

int main(int argc, char** argv){
    setName("compares two signed integers");
    registerTestlibCmd(argc, argv);
    
    readInput(inf);
    readOutput(ouf);
    readAns(ans);
    
    _checkSolution();
    
    quit(_ok, "all ok");
}
END
}

1;