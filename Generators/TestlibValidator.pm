package CATS::Formal::Generators::TestlibValidator;

use TestlibBase;
use parent -norequire, 'CATS::Formal::Generators::TestlibBase';

sub generate_description {
    my ($self, $fd) = @_;
    die "ROOT obj expected" if $fd->{type} != CATS::Formal::Constants::FD_TYPES->{ROOT}; 
    my $input = $fd->find_child_by_type(CATS::Formal::Constants::FD_TYPES->{INPUT});
    $self->{params} = {};
    %{$self->{params}} = %{$input->{attributes}};
    if (!exists $self->{params}->{strict}) {
        $self->{params}->{strict} = 1;
    }
    my @input_objects = map $self->generate_obj($_, '', 1) => @{$input->{children}};
    foreach my $obj (@input_objects){
        $self->{reader} .= $obj->{reader};
        next if $obj->{newline_obj};
        if ($self->{params}->{strict} && $obj->{space_reader} && $obj != $input_objects[-1]) {
            $self->{reader} .= $self->generate_readSpace("    ");
        }
        $self->{declarations} .= $obj->{declaration};
    }
}

sub pattern {
    my $self = shift;
    my $stream_name = $self->{stream_name};
    my $strict_mode = $self->{params}->{strict};
    my $strict = $strict_mode  ? 'true' : 'false';
    my $seekeof = $strict_mode ? '' : 'inf.seekEof();';
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

int main(int argc, char** argv){
    if (argc > 1){
        /*
            close up for CATS::Spawner
            it will be here while spawner can't redirect streams
        */
        freopen(argv[1], "r", stdin);
    }
    registerValidation();
    inf.strict = $strict;
    read_all(inf);
    $seekeof
    inf.readEof();
    return 0;
}
END
}

1;