package CATS::Formal::Generators::Testlib;
use strict;
use warnings;

use BaseGenerator; 
use lib '..';
use Constants qw(FD_TYPES);

use parent -norequire, 'CATS::Formal::Generators::BaseGenerator';

use constant FD_TYPES => CATS::Formal::Constants::FD_TYPES;

use constant FD_TYPE_TO_CPP_TYPE => {
    FD_TYPES->{INT} => 'long long',
    FD_TYPES->{FLOAT} => 'double',
    FD_TYPES->{STRING} => 'string'
};

use constant BAD_NAMES => {
    alignas => 1, 
    alignof => 1,
    and     => 1,
    and_eq  => 1,
    asm     => 1,
    auto    => 1,
    bitand  => 1,
    bitor   => 1,
    bool    => 1,
    break   => 1,
    case    => 1,
    catch   => 1,
    char    => 1,
    char16_t=> 1,
    char32_t=> 1,
    class   => 1,
    compl   => 1,
    const   => 1,
    constexpr=> 1,
    const_cast=> 1,
    continue=> 1,
    decltype=> 1,
    default => 1,
    delete  => 1,
    do      => 1,
    double  => 1,
    dynamic_cast=> 1,
    else    => 1,
    enum    => 1,
    explicit=> 1,
    export  => 1,
    extern  => 1,
    false   => 1,
    float   => 1,
    for     => 1,
    friend  => 1,
    goto    => 1,
    if      => 1,
    inline  => 1,
    int     => 1,
    long    => 1,
    mutable => 1,
    namespace=> 1,
    new     => 1,
    noexcept=> 1,
    not     => 1,
    not_eq  => 1,
    nullptr => 1,
    operator=> 1,
    or      => 1,
    or_eq=> 1,
    private=> 1,
    protected=> 1,
    public=> 1,
    register=> 1,
    reinterpret_cast=> 1,
    return=> 1,
    short=> 1,
    signed=> 1,
    sizeof=> 1,
    static=> 1,
    static_assert=> 1,
    static_cast=> 1,
    struct=> 1,
    switch=> 1,
    template=> 1,
    this=> 1,
    thread_local=> 1,
    throw => 1,
    true => 1,
    try => 1,
    typedef => 1,
    typeid => 1,
    typename => 1,
    union => 1,
    unsigned => 1,
    using => 1,
    virtual => 1,
    void => 1,
    volatile => 1,
    wchar_t => 1,
    while => 1,
    xor => 1,
    xor_eq => 1,
};

my $struct_counter = 0;
#$self->{description} = {
#   def_name => {real_name=>'', type=>$self->{types}}    
#}
my $stream_name = '__in__stream__';

sub generate {
    my ($self, $obj) = @_;
    $self->{definitions} = {};
    $self->{reader} = [];
    $self->{types} = {#%s - name of stream
        string => {
            usage  => 'string',
            name   => 'string',
            reader => '%s.readString()'
        },
        'long long' => {
            usage  => 'long long',
            name   => 'long long',
            reader => '%s.readLong()'
        },
        double => {
            usage  => 'double',
            name   => 'double',
            reader => '$s.readDouble()'
        }
    };
    $self->{structs} = {};
    $self->generate_description($obj);
    my $types_def = '';
    my $types_decl = '';
    foreach my $t (values $self->{types}) {
        my $def = $t->{definition};
        my $decl = $t->{declaration};
        if ($def) {
            $types_def .= "$def\n";
            $types_decl .= "$decl;\n";
        }
    }
    
    my $names = '';
    foreach my $n (keys $self->{definitions}){
        my $t = $self->{definitions}->{$n}->{type}->{usage};
        $names .= "$t $n;\n";
    }
    my $readers = $self->{main_reader};
    return <<"END"
#include "testlib.h"

using namespace std;

$types_decl

$names

$types_def

void read_all(InStream& $stream_name){
$readers
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


sub generate_description {
    my ($self, $fd) = @_;
    if ($fd->{type} == FD_TYPES->{ROOT}) {
        my $input = $fd->find_child_by_type(FD_TYPES->{INPUT});
        foreach my $child (@{$input->{children}}){
            $self->generate_description($child);
        }
        return;
    }
    
    my $r_name = $fd->{name};
    my $fd_type = $fd->{type};
    my $cpp_type_name = FD_TYPE_TO_CPP_TYPE->{$fd_type};
    my $cpp_type = $cpp_type_name ?
        $self->{types}->{$cpp_type_name} : $self->gen_cpp_struct($fd);
    if ($r_name) {
        my $def_name = $self->find_good_name($r_name);
        $self->{definitions}->{$def_name} = {real_name => $r_name, type => $cpp_type};
        $self->{main_reader} .= sprintf "    $def_name = " . $cpp_type->{reader} . ";\n", $stream_name;
    } else {
        $self->{main_reader} .= sprintf '    ' . $cpp_type->{reader} . ";\n", $stream_name;
    }
}

sub gen_cpp_struct {
    my ($self, $fd) = @_;
    my $struct = {name => 'SEQ_' . $struct_counter++, members => {}};
    $struct->{declaration} = 'struct '. $struct->{name};
    my $members_definition_code = '';
    my $members_reading_code = '';
    foreach my $member (@{$fd->{children}}){
        my $member_name = $member->{name};
        my $member_type = $member->{type};
        my $cpp_type_name = FD_TYPE_TO_CPP_TYPE->{$member_type};
        my $cpp_type = $cpp_type_name ?
            $self->{types}->{$cpp_type_name} : $self->gen_cpp_struct($member);
        my $member_reader = $cpp_type->{reader};
        if ($member_name) {
            my $m_name = $self->find_good_member_name($struct, $member_name);
            $members_definition_code .= '    ' . $cpp_type->{usage} . " $m_name;\n";
            $struct->{members}->{$m_name} = $cpp_type;
            $members_reading_code .= sprintf "        $m_name = $member_reader;\n", $stream_name;
        } else {
            $members_reading_code .= sprintf "        $member_reader;\n", $stream_name;
        }
        #TODO $member_reading_code .= "$constraints_code\n";
    }
    my $sname = $struct->{name};
    my $seq_reading_code = '';
    
    $struct->{usage} = "vector<$sname>";
    $struct->{reader} = "$sname :: read(%s)";
    $struct->{definition} = <<"END"
struct $sname {
$members_definition_code
    $sname(InStream& $stream_name) : {
$members_reading_code
    }
    static vector<$sname> read(InStream& $stream_name){
$seq_reading_code
    }
};
END
;
    $self->{code}->{declarations} .= $struct->{declaration} . ";\n";
    $self->{code}->{definitions} .= $struct->{definition} . "\n";
    $self->{types}->{$struct->{name}} = $struct;
    #$fd->{gen} = $struct;
    return $struct;
}

sub find_good_member_name {
    my ($self, $struct, $name) = @_;
    while (BAD_NAMES->{$name} || $struct->{members}->{$name}) {
        $name = '_' . $name . '_1';
    }
    return $name;
}

sub type_to_str {
    my $type = shift;
    return {
        FD_TYPES->{INT} => 'long long',
        FD_TYPES->{FLOAT} => 'long double',
        FD_TYPES->{STRING} => 'string',
        FD_TYPES->{SEQ} => 'vector',
        FD_TYPES->{SENTINEL} => 'vector'
    }
}

sub generate_expression {
    
}

sub find_good_name {
    my ($self, $name) = @_;
    while (BAD_NAMES->{$name} || $self->{definitions}->{$name}) {
        $name = "_$name" . '_1';
    }
    return $name;
}

<<END

#include "testlib.h"

using namespace std;

long long A = 0;
long double B = 0.0;
void readInput(){
    inf.readInt(1, 100);
    inf.readEoln();
    inf.readEof();
}

int main()
{
    registerValidation();
    
    readInput();

    return 0;
}

END
;
1;