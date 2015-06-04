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
        return 'CATS::Formal::Expressions::Integer' if $left->is_int && right->is_int;
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
    foreach my $param (@{$self->{params}}){
        $param->calc_type;
    }
    #TODO: check params
    return 'CATS::Formal::Expressions::Integer';
}

##############################################################################
package CATS::Formal::Expressions::Access;
use parent -norequire, 'CATS::Formal::Expressions::BaseExpression';
sub is_access{1;}

##############################################################################
package CATS::Formal::Expressions::MemberAccess;
#head - expr, member - fd
use parent -norequire , 'CATS::Formal::Expressions::Access';
sub is_member_access{1;}
sub stringify {
    $_[0]->{head}->stringify . '.' . $_[0]->{member}->{name};
}

sub calc_type {
    my ($self) = @_;
    #head check in parser
    return $self->{member}->to_expr_type;
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
    my $head = $self->{head}->calc_type;
    CATS::Fromal::Error::assert(!$head->is_array,"square brackers after non array");
    my $index = $self->{index}->calc_type;
    CATS::Formal::Error::assert(!$index->is_int, "index must be an integer");
    return 'CATS::Formal::Expressions::Record';
}
}

##############################################################################
package CATS::Formal::Expressions::Constant;
#$$self - scalar
use parent -norequire, 'CATS::Formal::Expressions::BaseExpression';
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

##############################################################################
package CATS::Formal::Expressions::String;
use parent -norequire , 'CATS::Formal::Expressions::Constant';
sub is_string{1;}
sub calc_type {'CATS::Formal::Expressions::String'}
sub type_as_str{'string'}

##############################################################################
package CATS::Formal::Expressions::Integer;
use parent -norequire , 'CATS::Formal::Expressions::Constant';
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

package CATS::Formal::Expressions::Record;
use parent -norequire, 'CATS::Formal::Expressions::Constant';
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

sub type_as_str {'array'}
1;