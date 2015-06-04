package CATS::Formal::Generators::TestlibBase;
use strict;
use warnings;

use lib '..';
use Generators::BaseGenerator;
use Constants;

use parent -norequire, 'CATS::Formal::Generators::BaseGenerator';

use constant FD_TYPES => CATS::Formal::Constants::FD_TYPES;
use constant TOKENS   => CATS::Formal::Constants::TOKENS;
use constant PRIORS   => CATS::Formal::Constants::PRIORS;

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
    $self->{names} = {};
    $self->{type_definitions} = '';
    $self->{type_declarations} = '';
    $self->{functions} = '';
    $self->{generated_functions} = {};
    $self->{definitions} = {};
    $self->{reader} = '';
    $self->{stream_name} = $stream_name;
    $self->generate_description($obj);
    return $self->pattern;
}

sub generate_description {
    die "call of abstract sub TestlibBase::generate_description";
}
sub pattern {
    die "call of abstract sub TestlibBase::pattern";
}

sub generate_int_obj {
    my ($self, $fd, $prefix, $deep) = @_;
    my $obj = {};
    my $spaces = '    ' x $deep;
    $obj->{name} = $self->find_good_name($fd->{name} || '_tmp_obj_');
    $obj->{name_for_expr} = $prefix . $obj->{name};
    $obj->{declaration} = "long long $obj->{name};\n";
    $fd->{obj} = $obj;
    my $range = $fd->{attributes}->{range};
    if ($range) {
        my $a = 0;
        my $b = 0;
        if ($range->is_array) {
            $a = $self->generate_expr($range->[0]);
            $b = $self->generate_expr($range->[1]);
        } else {
            $a = $b = $self->generate_expr($range);
        }
        $obj->{reader} = $spaces . "$obj->{name_for_expr} = $stream_name.readLong($a, $b, \"$obj->{name}\");\n"
    } else {
        $obj->{reader} = $spaces . "$obj->{name_for_expr} = $stream_name.readLong();\n";
    }
    $obj->{reader} .= $self->generate_constraints($fd, $spaces);
    $obj->{space_reader} = 1;
    
    return $obj;
}

sub generate_float_obj {
    my ($self, $fd, $prefix, $deep) = @_;
    my $obj = {};
    my $spaces = '    ' x $deep;
    $obj->{name} = $self->find_good_name($fd->{name} || '_tmp_obj_');
    $obj->{name_for_expr} = $prefix . $obj->{name};
    $obj->{declaration} = "double $obj->{name};\n";
    $fd->{obj} = $obj;
    my $range = $fd->{attributes}->{range};
    my $digits = $fd->{attributes}->{digits};
    my $a = '-numeric_limits<double>::max()';
    my $b = 'numeric_limits<double>::max()';
    my $read_func = "readDouble()";
    if ($range) {
        if ($range->is_array) {
            $a = $self->generate_expr($range->[0]);
            $b = $self->generate_expr($range->[1]);
        } else {
            $a = $b = $self->generate_expr($range);
        }
        $read_func = "readDouble($a, $b, \"$obj->{name}\")";
    }
    if ($digits) {
        my $dmin;
        my $dmax;
        if ($digits->is_array) {
            $dmin = $self->generate_expr($digits->[0]);
            $dmax = $self->generate_expr($digits->[1]);
        } else {
            $dmin = $dmax = $self->generate_expr($digits);
        }
        $read_func = "readStrictDouble($a, $b, $dmin, $dmax, \"$obj->{name}\")";
    }
    $obj->{reader} = $spaces . "$obj->{name_for_expr} = $stream_name.$read_func;\n" . 
        $self->generate_constraints($fd, $spaces);
    $obj->{space_reader} = 1;
    return $obj;
}


sub generate_string_obj {
    my ($self, $fd, $prefix, $deep) = @_;
    my $obj = {};
    my $spaces = '    ' x $deep;
    $obj->{name} = $self->find_good_name($fd->{name} || '_tmp_obj_');
    $obj->{name_for_expr} = $prefix . $obj->{name};
    
    $obj->{declaration} = "string $obj->{name};\n";
    $fd->{obj} = $obj;
    $obj->{reader} = $spaces . "$obj->{name_for_expr} = $stream_name.readWord();\n";
    my $lenrange = $fd->{attributes}->{lenrange};
    if ($lenrange) {
        if ($lenrange->is_array) {
            my $a = $self->generate_expr($lenrange->[0]);
            my $b = $self->generate_expr($lenrange->[1]);
            $obj->{reader} .= $spaces . $self->constraint_function(
                "$a <= $obj->{name_for_expr}.length() && $obj->{name_for_expr}.length() <= $b"
            );
        } else {
            $b = $self->generate_expr($lenrange);
            $obj->{reader} .= $spaces . $self->constraint_function(
                "$b == $obj->{name_for_expr}.length()"
            );
        }
    }
    my $chars = $fd->{attributes}->{chars};
    if ($chars) {
        $chars = $self->generate_expr($chars);
        $obj->{reader} .= $spaces . $self->constraint_function(
            "$obj->{name_for_expr}.find_first_not_of($chars) == string::npos"
        );
    }
    
    $obj->{reader} .= $self->generate_constraints($fd, $spaces);
    $obj->{space_reader} = 1;
    return $obj;
}

sub generate_seq_obj {
    my ($self, $fd, $prefix, $deep) = @_;
    my $obj = {};
    my $spaces = '    ' x $deep;
    $obj->{name} = $self->find_good_name($fd->{name} || '_tmp_obj_');
    $obj->{name_for_expr} = $prefix . $obj->{name};
    $fd->{obj} = $obj; 
     
    my $type = "SEQ_$struct_counter";
    my $seq_elem = $self->find_good_name($type.'_elem');
    
    $struct_counter++;
    $obj->{declaration} = "vector<$type> $obj->{name};\n";
    my $len = $fd->{attributes}->{length};
    if ($len) {
        my $e = $self->generate_expr($len);
        $obj->{reader} = $spaces."while($obj->{name_for_expr}.size() < $e){\n";
    } else {
        my $eof_reader = $self->{params}->{strict} ? 'eof()' : 'seekEof()';
        $obj->{reader} = $spaces."while(!$stream_name.$eof_reader){\n";
    }
    if ($self->{params}->{strict} && $fd->{children}->[-1]->{type} != FD_TYPES->{NEWLINE}) {
        $obj->{reader} .= "$spaces    if($obj->{name_for_expr}.size() > 0)\n"
            . $self->generate_readSpace("$spaces        ");
    }
    $obj->{reader} .= "$spaces    $type $seq_elem;\n";
    my ($members, $compare) = $self->generate_children($fd, $obj, $spaces, $deep);
    $obj->{reader} .= $spaces."    $obj->{name_for_expr}.push_back($seq_elem);\n" .
                      $spaces."}\n" . $self->generate_constraints($fd, $spaces);
    my $struct_definition = <<"END"    
struct $type {
$members
};
bool operator==(const $type& f, const $type& s){
    return $compare;
}

END
;
    $self->{type_declarations} .= "struct $type;\n"; 
    $self->{type_definitions} .= $struct_definition;
    $self->{space_reader} = 1;
    return $obj;
}

sub generate_children {
    my ($self, $fd, $obj, $spaces, $deep) = @_;    
    my @child_objects = map $self->generate_obj($_, "$obj->{name}.", $deep)
        => @{$fd->{children}};
    my $members = '';
    my @compare = ();
    foreach my $child_obj (@child_objects){
        $obj->{reader} .= $child_obj->{reader};
        next if $child_obj->{newline_obj};
        if ($self->{params}->{strict} && $child_obj->{space_reader} && $child_obj != $child_objects[-1]) {
            $obj->{reader} .= $self->generate_readSpace("$spaces    ");
        }
        $members .= '    ' . $child_obj->{declaration};
        push @compare, "f.$child_obj->{name} == s.$child_obj->{name}";
    }
    my $compare = join ' && ', @compare;
    return ($members, $compare);
}

sub generate_record_obj {
    my ($self, $fd, $prefix, $deep) = @_;
    my $obj = {};
    my $spaces = '    ' x $deep;
    $obj->{name} = $self->find_good_name(lc($fd->{name} || '_tmp_obj_'));
    $obj->{name_for_expr} = $prefix . $obj->{name};
    $fd->{obj} = $obj; 
    my $type = $obj->{type} = uc "_$obj->{name}_";
    $obj->{declaration} = "$type $obj->{name};\n";
    $obj->{reader} = '';
    my ($members, $compare) = $self->generate_children($fd, $obj, $spaces, $deep);
    $obj->{reader} .= $self->generate_constraints($fd, $spaces);
    my $struct_definition = <<"END"    
struct $type {
$members
};
bool operator==(const $type& f, const $type& s){
    return $compare;
}

END
;
    $self->{type_declarations} .= "struct $type;\n"; 
    $self->{type_definitions} .= $struct_definition;
    $self->{space_reader} = 1;
    return $obj;
}

sub generate_new_line_obj {
    my ($self, $fd, $prefix, $deep) = @_;
    my $spaces = '    ' x $deep;
    
    my $obj = {newline_obj => 1, reader => "$spaces$stream_name.seekEoln();\n"};
    if ($self->{params}->{strict}) {
        $obj->{reader} = "$spaces$stream_name.readEoln();\n";
    }
    if ($self->{last_obj}) {
        $self->{last_obj}->{space_reader} = undef; 
    }
    return $obj;    
}

sub generate_obj {
    my ($self, $fd, $prefix, $deep) = @_;
    my $gens = {
        FD_TYPES->{INT}     => 'generate_int_obj',
        FD_TYPES->{FLOAT}   => 'generate_float_obj',
        FD_TYPES->{STRING}  => 'generate_string_obj',
        FD_TYPES->{SEQ}     => 'generate_seq_obj',
        FD_TYPES->{RECORD}  => 'generate_record_obj',
        FD_TYPES->{NEWLINE} => 'generate_new_line_obj',
    };
    my $gen = $gens->{$fd->{type}};
    my $obj = $self->$gen($fd, $prefix, $deep);
    $self->{last_obj} = $obj;
    return $obj;
}

sub generate_readSpace {
    my ($self, $spaces) = @_;
    return "$spaces$stream_name.readSpace();\n";
}

sub find_good_name {
    my ($self, $name) = @_;
    while (BAD_NAMES->{$name} || $self->{names}->{$name}) {
        $name = "_$name" . '_';
    }
    #$self->{names}->{$name} = 1;
    return $name;
}

sub op_to_code {
    my $op = shift;
    my $ops = {
        TOKENS->{NOT}   => '!',
        #TOKENS->{POW}   => ,
        TOKENS->{MUL}   => '*',
        TOKENS->{DIV}   => '/',
        TOKENS->{MOD}   => '%',
        TOKENS->{PLUS}  => '+',
        TOKENS->{MINUS} => '-',
        TOKENS->{LT}    => '<',
        TOKENS->{GT}    => '>',
        TOKENS->{EQ}    => '==',
        TOKENS->{NE}    => '!=',
        TOKENS->{LE}    => '<=',
        TOKENS->{GE}    => '>=',
        TOKENS->{AND}   => '&&',
        TOKENS->{OR}    => '||',
    };
    return $ops->{$op};
}

sub generate_expr {
    my ($self, $expr) = @_;
    if ($expr->is_binary) {
        my $left = $self->generate_expr($expr->{left});
        my $right = $self->generate_expr($expr->{right});
        if ($expr->{op} == TOKENS->{POW}) {
            return "pow($left, $right)";
        }
        return "($left " . op_to_code($expr->{op}) . " $right)";
    } elsif ($expr->is_unary) {
        my $node = $self->generate_expr($expr->{node});
        return '('.op_to_code($expr->{op}) . "$node)";
    } elsif ($expr->is_variable) {
        return $expr->{fd}->{obj}->{name_for_expr};
    } elsif ($expr->is_array){
        die "not implemented";
    
    
    } elsif ($expr->is_string) {
        my $s = $$expr;
        return "\"$s\"";
    } elsif ($expr->is_constant) {
        return $$expr;
    } elsif ($expr->is_function) {
        my $params = join ',' , (map $self->generate_expr($_), @{$expr->{params}});
        $self->try_generate_function($expr);
        return "$expr->{name}($params)";
    } elsif ($expr->is_member_access) {
        my $head = $expr->{head};
        my $member = $expr->{member};
        #if ($head->is_array_access) {
            return $self->generate_expr($head) . '.' . $expr->{member}->{obj}->{name};
        #} else {
        #    die "not implemented";
        #}
    
    } elsif ($expr->is_array_access) {
        return $self->generate_expr($expr->{head}) . '[' . $self->generate_expr($expr->{index}) . ']';
    } else {die "wtf"}
    
}

sub try_generate_function {
    my ($self, $func) = @_;
    my $name = $func->{name};
    my $params = $func->{params};
    if (!$self->{generated_functions}->{vector_length} &&
        $name eq 'length' &&
        $#{$params} == 0 &&
        $params->[0]->is_variable &&
        $params->[0]->{fd}->{type} == FD_TYPES->{SEQ})
    {
        my $res = <<"FUNC"
template <class T>
int length(vector<T> v){
    return v.size();
}
FUNC
;
        $self->{functions} .= $res;
        $self->{generated_functions}->{vector_length} = 1;
        return;
    } elsif (!$self->{generated_functions}->{string_length} &&
        $name eq 'length' &&
        $#{$params} == 0 && (
            $params->[0]->is_variable &&
            $params->[0]->{fd}->{type} == FD_TYPES->{STRING}
        ||
            $params->[0]->is_string
        )
    ) {
        my $res = <<"END"
int length(string& str){
    return str.length();
}
END
;
        $self->{functions} .= $res;
        $self->{generated_functions}->{string_length} = 1;
        return;
    }
}

sub constraint_function {
    my ($self, $condition_code) = @_;
    return "ensure($condition_code);\n";
}

sub generate_constraint {
    my ($self, $constraint) = @_;
    my $c = $self->generate_expr($constraint);
    return $self->constraint_function($c);
}

sub generate_constraints {
    my ($self, $fd, $spaces) = @_;
    my $res = '';
    foreach my $c (@{$fd->{constraints}}){
        my $code = $self->generate_constraint($c);
        $res .= "$spaces$code";
    }
    return $res;
}

1;