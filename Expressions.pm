use strict;
use warnings;
use Error;
use Constants;
    
package CATS::Formal::Expressions::BaseExpression;
use Base;
use parent -norequire, 'CATS::Formal::BaseObj';

sub is_expr {1;}
sub new {
    my ($class) = shift;
    my $self = { @_ };
    bless $self, $class;
}

sub is_access {0;}
sub is_variable {0;}
sub is_member_access {0;}
sub is_array_access{0;}
sub is_binary {0;}
sub is_unary {0;}
sub is_constant{0;}
sub is_array{0;}
sub is_function{0;}
sub is_float{0;}
sub is_int{0;}
sub is_string{0;}
sub is_number{0;}
sub is_record{0;}

sub calc_type {
    die "abstract method called BaseExpression::calc_type";
}

sub evaluate {
    die "abstract method called BaseExpression::evaluate";    
}

##############################################################################
package CATS::Formal::Expressions::Binary;
BEGIN {CATS::Formal::Constants->import()}
# left - expr, right - expr, op - token
use parent -norequire , 'CATS::Formal::Expressions::BaseExpression';
sub is_access { $_[0]->{is_access};}
sub is_binary{1;}
sub stringify {
    $_[0]->{left}->stringify . $_[0]->{op} . $_[0]->{right}->stringify;
}
#int, float, string, array
sub calc_type {
    my ($self) = @_;
    my $left = $self->{left}->calc_type;
    my $right = $self->{right}->calc_type;
    if (grep $self->{op} == $_ => @{TOKENS()}{qw(LT GT EQ NE LE GE)}) {
        return 'CATS::Formal::Expressions::Integer' if
            $left->is_number && $right->is_number ||
            $left->is_string && $right->is_string;
        CATS::Formal::Error::set("types $left and $right not comparable");
    }
    
    if (grep $self->{op} == $_ => @{TOKENS()}{qw(AND OR)}) {
        return 'CATS::Formal::Expressions::Integer' if $left->is_int && $right->is_int;
        CATS::Formal::Error::set("operands for '&&' and '||' should be integers");
    }
    
    if (grep $self->{op} == $_ => @{TOKENS()}{qw(POW MUL DIV MOD PLUS MINUS)}) {
        if ($left->is_int && $right->is_int) {
            return 'CATS::Formal::Expressions::Integer';
        } elsif ($left->is_number && $right->is_number) {
            return 'CATS::Formal::Expressions::Float';
        }
    }
    my $s = TOKENS_STR()->{$self->{op}};
    my $t1 = $left->type_as_str;
    my $t2 = $right->type_as_str;
    CATS::Formal::Error::set("wrong types for operator '$s' got '$t1 $s $t2'");
}

sub _pow   {$_[0] ** $_[1]}
sub _mul   {$_[0] *  $_[1]}
sub _plus  {$_[0] +  $_[1]}
sub _minus {$_[0] -  $_[1]}
sub _div   {$_[0] /  $_[1]}
sub _mod   {$_[0] %  $_[1]}
sub _eq    {$_[0] == $_[1]}
sub _gt    {$_[0] >  $_[1]}
sub _lt    {$_[0] <  $_[1]}
sub _ne    {$_[0] != $_[1]}
sub _le    {$_[0] <= $_[1]}
sub _ge    {$_[0] >= $_[1]}

sub evaluate_and {
    my ($self, $val) = @_;
    my $left = $self->{left}->evaluate($val);
    return CATS::Formal::Expressions::Integer->new(0) unless ($left);
    my $res = $self->{right}->evaluate($val) ? 1 : 0;
    return CATS::Formal::Expressions::Integer->new($res);
}

sub evaluate_or {
    my ($self, $val) = @_;
    my $left = $self->{left}->evaluate($val);
    return CATS::Formal::Expressions::Integer->new(1) if $left;
    my $res = $self->{right}->evaluate($val) ? 1 : 0;
    return CATS::Formal::Expressions::Integer->new($res);
}

sub evaluate {
    my ($self, $val) = @_;
    if (TOKENS()->{AND} == $self->{op}) {
        return $self->evaluate_and($val);
    }
    if (TOKENS()->{OR} == $self->{op}) {
        return $self->evaluate_or($val);
    }
    
    my $left = $self->{left}->evaluate($val);
    my $right = $self->{right}->evaluate($val);
    my %op = (
        TOKENS()->{POW}   => \&_pow,
        TOKENS()->{MUL}   => \&_mul,
        TOKENS()->{DIV}   => \&_div,
        TOKENS()->{MOD}   => \&_mod,
        TOKENS()->{PLUS}  => \&_plus,
        TOKENS()->{MINUS} => \&_minus,
        TOKENS()->{AND}   => \&_and,
        TOKENS()->{OR}    => \&_or,
        TOKENS()->{EQ}    => \&_eq,
        TOKENS()->{LT}    => \&_lt,
        TOKENS()->{GT}    => \&_gt,
        TOKENS()->{NE}    => \&_ne,
        TOKENS()->{GE}    => \&_ge,
        TOKENS()->{LE}    => \&_le,
    );
    return $op{$self->{op}}->($left, $right);
}

##############################################################################
package CATS::Formal::Expressions::Unary;
BEGIN {CATS::Formal::Constants->import()}
#op - token, node - expr
use parent -norequire , 'CATS::Formal::Expressions::BaseExpression';
sub is_unary{1;}
sub stringify {
    $_[0]->{op} . $_[0]->{node};
}
sub calc_type {
    my ($self) = @_;
    my $type = $self->{node}->calc_type;
    my $s = TOKENS_STR()->{$self->{op}};
    my $t = $type->type_as_str;
    CATS::Formal::Error::set(
        "operand for unary operator '$s' should be a number " .
        "but got '$s$t'"
    ) unless $type->is_number;
    $self->{op} == TOKENS()->{NOT} && return 'CATS::Formal::Expressions::Integer';
    return $type;
}

sub _not   {!$_[0]}
sub _plus  {+$_[0]}
sub _minus {-$_[0]}

sub evaluate {
    my ($self, $val) = @_;
    my $e = $self->{node}->evaluate($val);
    my %op = (
        TOKENS()->{NOT} => \&_not,
        TOKENS()->{PLUS} => \&_plus,
        TOKENS()->{MINUS} => \&_minus,
    );
    return $op{$self->{op}}->($e);
}

##############################################################################
package CATS::Formal::Expressions::Variable;
#fd - fd
use parent -norequire , 'CATS::Formal::Expressions::BaseExpression';
sub is_variable {1;}
sub stringify {
    $_[0]->{fd}->{name};
}
sub calc_type {
    $_[0]->{fd}->to_expr_type;
}

sub evaluate {
    my ($self, $val) = @_;
    my $v = $self->{fd}->find_self_val($val);
    $v ||
      CATS::Formal::Error::set("don't know the value of '$self->{fd}->{name}'");
    return $v->{val};    
}

##############################################################################
package CATS::Formal::Expressions::Function;
#name - string, params - [expr]
use parent -norequire , 'CATS::Formal::Expressions::BaseExpression';
sub is_function{1;}
sub stringify {
    my $self = shift;
    return $self->{name} . '(' . (join ',', (map $_->stringify, $self->{params})) . ')';
}

sub calc_type {
    my ($self) = @_;
    #foreach my $param (@{$self->{params}}){
    #    $param->calc_type;
    #}
    return $self->{func}->{return};
}

sub evaluate {
    my ($self, $val) = @_;
    my @params = map $_->evaluate($val), @{$self->{params}};
    return $self->{func}->{calc}->(@params);
}

##############################################################################
package CATS::Formal::Expressions::Access;
use parent -norequire, 'CATS::Formal::Expressions::BaseExpression';
sub is_access{1;}

##############################################################################
package CATS::Formal::Expressions::MemberAccess;
#head - expr, member - fd
use parent -norequire , 'CATS::Formal::Expressions::Access';
use List::Util qw(first);
sub is_member_access{1;}
sub stringify {
    $_[0]->{head}->stringify . '.' . $_[0]->{member}->{name};
}

sub calc_type {
    my ($self) = @_;
    return $self->{member}->to_expr_type;
}

sub evaluate {
    my ($self, $val) = @_;
    my $v = $self->{head}->evaluate($val);
    my $p = first {$_->{fd} == $self->{member}} @{$v};
    return $p->{val}; 
}

##############################################################################
package CATS::Formal::Expressions::ArrayAccess;
use parent -norequire, 'CATS::Formal::Expressions::Access';
sub is_array_access{1;}
sub stringify {
    $_[0]->{head}->stringify . '[' . $_[0]->{index}->stringify . ']';
}
sub calc_type {
    my ($self) = @_;
    #my $head = $self->{head}->calc_type;
    #CATS::Fromal::Error::assert(!$head->is_array,"square brackers after non array");
    #my $index = $self->{index}->calc_type;
    #CATS::Formal::Error::assert(!$index->is_int, "index must be an integer");
    return 'CATS::Formal::Expressions::Record';
}

sub evaluate {
    my ($self, $val) = @_;
    my $head = $self->{head}->evaluate($val);
    my $index = $self->{index}->evaluate($val);
    return $head->[$$index]; 
}

##############################################################################
package CATS::Formal::Expressions::Constant;
#$$self - scalar

use parent -norequire, 'CATS::Formal::Expressions::BaseExpression';
use overload
    '+'   => \&_plus,
    '-'   => \&_minus,
    '*'   => \&_mul,
    '/'  => \&_div,
    '%'   => \&_mod,
    '**'  => \&_pow,
    #'||'  => \&_or,
    #'&&'  => \&_and,
    '=='  => \&_eq,
    '<'   => \&_lt,
    '>'   => \&_gt,
    '!='  => \&_ne,
    '<='  => \&_le,
    '>='  => \&_ge,
    'neg' => \&_neg,
    '!'   => \&_not,
    'bool' => \&_bool,
    '""'  => \&stringify;

sub is_constant{1;}
sub new {
    my $class = shift; 
    my $val = shift; #take scalar
    my $self = \$val;
    return bless $self, $class;
}

sub stringify {
    my $self = shift;
    $$self;
}

sub evaluate {
    $_[0];
}

use constant Integer => 'CATS::Formal::Expressions::Integer';
use constant Float   => 'CATS::Formal::Expressions::Float';

sub err {
    CATS::Formal::Error::set(@_);
}

sub _bool {
    my ($self) = @_;
    if ($self->is_array || $self->is_record) {
        return @$self;
    }
       
    return $$self;
}

sub _pow {
    my ($left, $right) = @_;
    if ($left->is_int && $right->is_int) {
        return Integer->new($$left ** $$right);
    } elsif ($left->is_number && $right->is_number) {
        return Float->new($$left ** $$right);
    }
    err("can't to pow $left and $right");
}

sub _mul {
    my ($left, $right) = @_;
    if ($left->is_int && $right->is_int) {
        return Integer->new($$left * $$right);
    } elsif ($left->is_number && $right->is_number) {
        return Float->new($$left * $$right);
    }
    err("can't to mul $left and $right");
}

sub _plus {
    my ($left, $right) = @_;
    if ($left->is_int && $right->is_int) {
        return Integer->new($$left + $$right);
    } elsif ($left->is_number && $right->is_number) {
        return Float->new($$left + $$right);
    }
    err("can't to sum $left and $right");
}
sub _minus {
    my ($left, $right) = @_;
    if ($left->is_int && $right->is_int) {
        return Integer->new($$left - $$right);
    } elsif ($left->is_number && $right->is_number) {
        return Float->new($$left - $$right);
    }
    err("can't to sub $left and $right");
}

sub _div {
    my ($left, $right) = @_;
    if ($left->is_int && $right->is_int) {
        return Integer->new($$left / $$right);
    } elsif ($left->is_number && $right->is_number) {
        return Float->new($$left / $$right);
    }
    err("can't to div $left and $right");
}

sub _mod {
    my ($left, $right) = @_;
    if ($left->is_int && $right->is_int) {
        return Integer->new($$left % $$right);
    } elsif ($left->is_number && $right->is_number) {
        return Float->new($$left % $$right);
    }
    err("can't to mul $left and $right");
}

#sub _and   {$_[0] && $_[1]}
#sub _or    {$_[0] || $_[1]}
sub _eq {
    my ($left, $right) = @_;
    if ($left->is_number && $right->is_number) {
        return Integer->new($$left == $$right);
    } elsif ($left->is_string && $right->is_string) {
        return Integer->new($$left eq $$right);
    }
    err("can't to compare $left and $right");
}

sub _gt {
    my ($left, $right) = @_;
    if ($left->is_number && $right->is_number) {
        return Integer->new($$left > $$right);
    } elsif ($left->is_string && $right->is_string) {
        return Integer->new($$left gt $$right);
    }
    err("can't to compare $left and $right");
}

sub _lt {
    my ($left, $right) = @_;
    if ($left->is_number && $right->is_number) {
        return Integer->new($$left < $$right);
    } elsif ($left->is_string && $right->is_string) {
        return Integer->new($$left lt $$right);
    }
    err("can't to compare $left and $right");
}

sub _ne {
    my ($left, $right) = @_;
    if ($left->is_number && $right->is_number) {
        return Integer->new($$left != $$right);
    } elsif ($left->is_string && $right->is_string) {
        return Integer->new($$left ne $$right);
    }
    err("can't to compare $left and $right");
}

sub _le  {
    my ($left, $right) = @_;
    if ($left->is_number && $right->is_number) {
        return Integer->new($$left <= $$right);
    } elsif ($left->is_string && $right->is_string) {
        return Integer->new($$left le $$right);
    }
    err("can't to compare $left and $right");
}

sub _ge {
    my ($left, $right) = @_;
    if ($left->is_number && $right->is_number) {
        return Integer->new($$left >= $$right);
    } elsif ($left->is_string && $right->is_string) {
        return Integer->new($$left ge $$right);
    }
    err("can't to compare $left and $right");
}

sub _neg {
    my ($self) = @_;
    if ($self->is_number) {
        return Integer->new(-$$self);
    }
    err("can't to negate $self");
}

sub _not {
    my ($self) = @_;
    if ($self->is_int) {
        my $r = $$self == 0 ? 1 : 0;
        return Integer->new($r);
    }
    err("can't to not $self");
}

##############################################################################
package CATS::Formal::Expressions::String;
use parent -norequire , 'CATS::Formal::Expressions::Constant';
sub is_string{1;}
sub calc_type {'CATS::Formal::Expressions::String'}
sub type_as_str{'string'}

##############################################################################
package CATS::Formal::Expressions::Integer;
use parent -norequire , 'CATS::Formal::Expressions::Constant';
use POSIX qw(floor);
sub new {
    my ($class, $val) = @_; 
    $val = floor($val);
    my $self = \$val;
    return bless $self, $class;
}
sub is_int{1;}
sub is_number{1;}
sub calc_type {'CATS::Formal::Expressions::Integer'}
sub type_as_str {'integer'}

##############################################################################
package CATS::Formal::Expressions::Float;
use parent -norequire , 'CATS::Formal::Expressions::Constant';
sub is_number{1;}
sub is_float{1;}
sub calc_type {'CATS::Formal::Expressions::Float'}
sub type_as_str{'float'}

##############################################################################
#[{fd=> fd, val=>expr}]
package CATS::Formal::Expressions::Record;
use parent -norequire, 'CATS::Formal::Expressions::Constant';
sub new {
    my ($class, $arr) = @_;
    return bless $arr, $class;
}
sub stringify {
    my ($self) = @_;
    return '{' . (join ', ', (map $_->stringify, @{$self})) . '}';
}
sub evaluate {
    my ($self, $val) = @_;
    my @arr = map {fd => $_, val => $_->{val}->evaluate($val)}, @{$self};
    return CATS::Formal::Expressions::Record->new(\@arr);
}

sub is_record{1;}
sub calc_type{'CATS::Formal::Expressions::Record'}
sub type_as_str{'record'}
##############################################################################
package CATS::Formal::Expressions::Array;
#@$self
use parent -norequire , 'CATS::Formal::Expressions::Constant';
sub is_array{1;}

sub new {
    my ($class, $arr) = @_;
    return bless $arr, $class;
}

sub stringify {
    my $self = shift;
    return '[' . (join ', ', (map $_->stringify, @{$self})) . ']';
}

sub calc_type {
    my ($self) = @_;
    my @arr = map $_->calc_type, @{$self};
    return CATS::Formal::Expressions::Array->new(\@arr);
}

sub evaluate {
    my ($self, $val) = @_;
    my @arr = map $_->evaluate($val), @{$self};
    return CATS::Formal::Expressions::Array->new(\@arr);
}

sub type_as_str {'array'}
1;