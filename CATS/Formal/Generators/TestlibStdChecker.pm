package CATS::Formal::Generators::TestlibStdChecker;

use strict;
use warnings;

use parent 'CATS::Formal::Generators::TestlibChecker';

sub generate_description {
    my ($self, $fd) = @_;
    die "expect ROOT object" if $fd->{type} != CATS::Formal::Constants::FD_TYPES->{ROOT};
    my $stream_name = $self->{stream_name};
    my @keys = qw(INPUT OUTPUT);
    my %tresult = (
        INPUT => '_fail',
        ANSWER => '_fail',
        OUTPUT => '_pe',
    );
    my %stream = (
        INPUT => 'inf',
        ANSWER => 'ans',
        OUTPUT => 'ouf'
    );
    $self->{objs} = {};
    my $check_solution = '';
    my $read_all ="void read_all(){\n";
    foreach my $k (@keys){
        my $obj = $self->generate_top($fd, $k) || next;
        $read_all .= "    read_$obj->{name}($obj->{name_for_expr}, $stream{$k}, $tresult{$k});\n";
        if ($k eq 'OUTPUT') {
            $self->{type_declarations} .= "typedef _OUTPUT_ _ANSWER_;\n";
            $self->{declarations} .= "_ANSWER_ answer;\n";
            $read_all .= "    read_$obj->{name}(answer, $stream{ANSWER}, $tresult{ANSWER});\n";
            $check_solution = '_test_(answer == output, _wa);';
        }
    }
    $read_all .= "}\n";
    $self->{functions} .= $read_all;
    $self->{functions} .= <<"END"

int main(int argc, char** argv) {
    registerTestlibCmd(argc, argv);
    read_all();
    $check_solution
    quit(_ok, "looks good");
}
END

}

1;
