package CATS::Formal::Generators::TestlibValidator;

use TestlibBase;
use parent -norequire, 'CATS::Formal::Generators::TestlibBase';

sub generate_description {
    my ($self, $fd) = @_;
    if ($fd->{type} == CATS::Formal::Constants::FD_TYPES->{ROOT}) {
        my $input = $fd->find_child_by_type(CATS::Formal::Constants::FD_TYPES->{INPUT});
        foreach my $child (@{$input->{children}}){
            my $obj = $self->generate_obj($child, '', 1);
            $self->{reader} .= $obj->{reader};
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

void read_all(InStream& $stream_name){
$self->{reader}
}

int main(){
    registerValidation();
    inf.strict = false;
    read_all(inf);
    inf.readEoln();
    inf.readEof();
    return 0;
}
END
}

1;