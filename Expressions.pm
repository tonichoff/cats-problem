package CATS::Formal::Expressions::BaseExpression;
use strict;
use warnings;

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

sub is_member_acces {0;}
sub is_binary {0;}

package CATS::Formal::Expressions::Binary;

use parent -norequire , 'CATS::Formal::Expressions::BaseExpression';

sub is_access { $_[0]->{is_access};}

sub is_binary{1;}

sub stringify {
    $_[0]->{left}->stringify . $_[0]->{op} . $_[0]->{right}->stringify;
}

package CATS::Formal::Expressions::Unary;

use parent -norequire , 'CATS::Formal::Expressions::BaseExpression';

sub stringify {
    $_[0]->{op} . $_[0]->{node};
}

package CATS::Formal::Expressions::Variable;

use parent -norequire , 'CATS::Formal::Expressions::BaseExpression';

sub is_variable {1;}

sub stringify {
    $_[0]->{fd}->{name};
}


package CATS::Formal::Expressions::Function;

use parent -norequire , 'CATS::Formal::Expressions::BaseExpression';

sub stringify {
    my $self = shift;
    return $self->{name} . '(' . (join ',', (map $_->stringify, $self->{params})) . ')';
}

package CATS::Formal::Expressions::MemberAccess;

use parent -norequire , 'CATS::Formal::Expressions::BaseExpression';

sub is_access {1;}

sub is_member_access{1;}

sub stringify {
    $_[0]->{head}->stringify . '.' . $_[0]->{member}->{name};
}

package CATS::Formal::Expressions::Constant;

use parent -norequire, 'CATS::Formal::Expressions::BaseExpression';

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

package CATS::Formal::Expressions::String;

use parent -norequire , 'CATS::Formal::Expressions::Constant';



package CATS::Formal::Expressions::Integer;

use parent -norequire , 'CATS::Formal::Expressions::Constant';



package CATS::Formal::Expressions::Float;

use parent -norequire , 'CATS::Formal::Expressions::Constant';


package CATS::Formal::Expressions::Array;

use parent -norequire , 'CATS::Formal::Expressions::Constant';

sub new {
    my $class = shift;
    my $arr = shift;
    return bless $arr, $class;
}

sub stringify {
    my $self = shift;
    return '[' . (join ', ', (map $_->stringify, @{$self})) . ']';
}

1;