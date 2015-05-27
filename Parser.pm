use strict;
use warnings;

package CATS::Formal::Parser::Base;

sub new {
    my ($class) = shift;
    my $self = { @_ };
    bless $self, $class;
    $self;
}

sub parse {
    my $self = shift;
    my $str = shift;
    $self->_init($str);
    my $res;
    eval {
        $res = $self->_parse_start;
    };
    die $@ if !$self->{error} && $@;
    $self->_finish;
    $res;
}

sub parseOutput {
    my ($self, $fd, $str) = @_;
    $self->_init($str);
    my $res;
    eval {$res = $self->_parse_output($fd);};
    die $@ if $@;
    $self->_finish;
    $res;
}

sub _init {
    die "called abstract method Parser::parse_start";    
}

sub _parse_start {
    die "called abstract method Parser::parse_start";
}

sub _finish {
    die "called abstract method Parser::finish";
}

package CATS::Formal::Parser;

use Description;
use Expressions;
use Constants;

use parent -norequire, 'CATS::Formal::Parser::Base';

use constant {
    TOKEN_TYPES => CATS::Formal::Constants::TOKEN_TYPES,
    TOKENS      => CATS::Formal::Constants::TOKENS,
    STR_TOKENS  => CATS::Formal::Constants::STR_TOKENS,
    PRIORS      => CATS::Formal::Constants::PRIORS,
    FD_TYPES    => CATS::Formal::Constants::FD_TYPES,
    PREF_PRIOR  => CATS::Formal::Constants::PREF_PRIOR,
    CMP_PRIOR   => CATS::Formal::Constants::CMP_PRIOR
};
my %tmp = reverse %{STR_TOKENS()};
use constant TOKENS_STR => \%tmp;

my @patterns = (
    '[0-9]+\.[0-9]+([eE][-+]?[0-9]+)?' => TOKEN_TYPES->{CONSTANT_FLOAT},
    '\d+' => TOKEN_TYPES->{CONSTANT_INT}, 
    '\w+' => TOKEN_TYPES->{WORD},
    "'.*?'" => TOKEN_TYPES->{CONSTANT_STR},
    '>=|<=|<>|==|!=|&&|\|\||[-.+*\/%\[\]^=()<>!,;#]' => TOKEN_TYPES->{OPERATOR},
);

#sub  trim { my $s = shift; $s =~ s/^\s+|\s+$//g; return $s };

sub _next_token {
    my $self = shift;
    $self->{pos} += length $self->{token_str};
    $self->{col} += length $self->{token_str};
    my $src = \$self->{src};
    if ($$src eq '') {
        $self->{token_type} = TOKEN_TYPES->{EOF},
        $self->{token} = TOKENS->{EOF},
        $self->{token_str} = '';
        return ($self->{token_type}, $self->{token}, $self->{token_str});
    }
    
    my $type = TOKEN_TYPES->{UNKNOWN};
    my $spaces;
    my $token_str;
    my $token;
    #TODO:float?
    for(my $i = 0; $i < $#patterns; $i += 2){
        my $pat = $patterns[$i];
        if ($$src =~ /^(\s*)($pat)/s) {
            $spaces = $1;
            $token_str = $2;
            $$src = $';
            $token = STR_TOKENS->{$token_str} || TOKENS->{UNKNOWN};
            $type = $patterns[$i + 1];
            my @spaces = split '' => $spaces;
            foreach (@spaces) {
                ++$self->{pos};
                if ($_ eq "\n") {
                    $self->{col} = 1;
                    ++$self->{row};
                } elsif (/\s/) {
                    ++$self->{col};
                } else {
                    die "BUG in position calc";
                }
            }
            last;
        }
    }
    if ($type == TOKEN_TYPES->{UNKNOWN}) {
        my $char = substr($$src, 0, 1);;
        $self->error("unknown token '$char'");    
    };
    
    #my $rtype = $RTOKEN_TYPES{$type};
    #print "$token $rtype\n";
    $self->{token_type} = $type;
    $self->{token} = $token;
    $self->{token_str} = $token_str;
    return ($token_str, $token, $type);
}

sub _assert {
    my ($self, $b, $f) = @_;
    if ($b) {
        $self->error($f);
    }
}

sub _init {
    my $self = shift;
    $self->{src}    = shift;
    $self->{pos}    = 0;
    $self->{col}    = 1;
    $self->{row}    = 1;
    $self->{curParent} = undef;
    $self->{token} = undef;
    $self->{token_type} = undef;
    $self->{token_str} = '';
    $self->{error}  = undef;
}

sub _parse_start {
    my $self = shift;
    $self->_next_token;
    $self->_parse_fd;
}

sub _finish {
    my ($self) = @_;
    delete @{$self}{qw(src pos col row curParent token_type token token_str)};
}

sub _expect {
    my ($self, $expected) = @_;
    my $s = TOKENS_STR->{TOKENS->{$expected}};
    $self->_assert($self->{token} != TOKENS->{$expected}, "expected '$s' instead '$self->{token_str}'");
}

sub _expect_identifier {
    my ($self, $expected) = shift;
    $self->_assert($self->{token_type} != TOKEN_TYPES->{WORD},
                   "expected identifier instead '$self->{token_str}'");
}

sub _prior {
    PRIORS->{$_[0]->{token}} || 100;
}

sub _parse_comma_delimeted_exprs {
    my ($self, $end_token) = @_;
    my $arr = [];
    my $token = \$self->{token};
    if ($$token != TOKENS->{$end_token}) {
        $self->_assert($$token == TOKENS->{COMMA}, "expected expression got ','");
        do {
            $self->_next_token if $$token == TOKENS->{COMMA};
            push @$arr, $self->_parse_expr_p(1);
        } while ($$token == TOKENS->{COMMA});
    }
    $self->_expect($end_token);
    $self->_next_token;
    return $arr;
}
    
sub _parse_func {
    my ($self, $name) = @_;
    $self->_next_token;
    my $params = $self->_parse_comma_delimeted_exprs('RPAREN');
    return CATS::Formal::Expressions::Function->new(name => $name, params => $params);
}

sub _member_access_new {
    my ($self, $head, $parent, $name) = @_;
    my $member = $parent->find_child($name);
    $self->_assert(!$member, "cant find member '$name'");
    
    return CATS::Formal::Expressions::MemberAccess->new(head => $head, member => $member);
}

sub _parse_member_access {
    # wtf?
    my ($self, $head, $member) = @_;
    if ($head->is_variable){
        $self->_assert($head->{fd}->{type} != FD_TYPES->{SEQ},
                       "trying to get member from type without members");
        return $self->_member_access_new($head, $head->{fd}, $member);
    } elsif ($head->is_member_access){
        return $self->_member_access_new($head, $head->{member}, $member);
    } elsif ($head->is_array_access){
        my $left = $head->{head};
        if ($left->is_member_access){
            return $self->_member_access_new($head, $left->{member}, $member);
        } elsif ($left->is_variable){
            $self->_assert($left->{fd}->{type} != FD_TYPES->{SEQ},
                           "trying to get member from type without members");
            return $self->_member_access_new($head, $left->{fd}, $member);
        }
    } else {
        warn "bug in parser";
        $self->error("BUG");
    }
}

sub _parse_access {
    my ($self, $name) = @_;
    my $root = CATS::Formal::Expressions::Variable->new(fd => $self->{fd}->find($name));
    my $token = \$self->{token};
    while($$token == TOKENS->{LQBR} || $$token == TOKENS->{DOT}){
        #$self->_next_token;
        if ($$token == TOKENS->{LQBR}){
            $self->_assert(!$root->is_variable, "square brackets after non variable");
            #$self->_assert(!$root->is_access, "square brackets after non variable");
            $self->_next_token; #TODO: check this and next line right=>$self->_parse_factor
            $root = CATS::Formal::Expressions::ArrayAccess->new(head => $root, index => $self->_parse_expr_p(1));
            $self->_expect('RQBR');
            $self->_next_token;
        } else {
            $self->_next_token;
            $self->_expect_identifier;
            $root = $self->_parse_member_access($root, $self->{token_str});
            $self->_next_token;
        }
    }
    return $root;
}

sub _parse_factor {
    my $self = shift;
    my $ttype = \$self->{token_type};
    my $token = \$self->{token};
    if($$ttype == TOKEN_TYPES->{WORD}){
        my $name = $self->{token_str};
        $self->_next_token;
        my $res;
        if ($$token == TOKENS->{LPAREN}){
            $res = $self->_parse_func($name);
        } elsif ($$token == TOKENS->{DOT} || $$token == TOKENS->{LQBR}){
            $res = $self->_parse_access($name);
        } else {
            my $fd = $self->{fd}->find($name);
            $self->_assert(!$fd, "undefined variable with name '$name'");
            $res = CATS::Formal::Expressions::Variable->new(fd => $fd);
        }
        return $res;
    } elsif ($$ttype == TOKEN_TYPES->{CONSTANT_INT}) {
        my $r = CATS::Formal::Expressions::Integer->new($self->{token_str});
        $self->_next_token;
        return $r;
    } elsif ($$ttype == TOKEN_TYPES->{CONSTANT_FLOAT}) {
        my $f = CATS::Formal::Expressions::Float->new($self->{token_str});
        $self->_next_token;
        return $f;
    } elsif ($$ttype == TOKEN_TYPES->{CONSTANT_STR}) {
        $self->{token_str} =~ /'(.*)'/;
        my $s = CATS::Formal::Expressions::String->new($1);
        $self->_next_token;
        return $s;
    } elsif ($$token == TOKENS->{LPAREN}){
        $self->_next_token;
        my $e = $self->_parse_expr_p(1);
        $self->_expect('RPAREN');
        $self->_next_token;
        return $e;
    } elsif ($$token == TOKENS->{LQBR}){
        $self->_next_token;
        my $arr = $self->_parse_comma_delimeted_exprs('RQBR');
        return CATS::Formal::Expressions::Array->new($arr);
    } else {
        $self->error("expected one of 'identifier, integer, float, string, (, [', got '$self->{token_str}'");
    }
}

sub _parse_prefix {
    my $self = shift;
    my @pref_tokens = (TOKENS->{NOT}, TOKENS->{PLUS}, TOKENS->{MINUS});
    if (grep $_ == $self->{token}, @pref_tokens) {
        my $op = $self->{token};
        $self->_next_token;
        return CATS::Formal::Expressions::Unary->new(op => $op, node => $self->_parse_prefix);
    }
    return $self->_parse_factor;
}

sub _parse_cmp {
    my ($self, $cur_prior) = @_;
    my $left = $self->_parse_expr_p($cur_prior + 1);
    my $op;
    while($cur_prior == $self->_prior){
        my $t = $self->{token};
        $self->_next_token;
        my $right = $self->_parse_expr_p($cur_prior + 1);
        my $new_op = CATS::Formal::Expressions::Binary->new(op => $t, left => $left, right => $right);
        $op = $op ? CATS::Formal::Expressions::Binary->new(op => TOKENS->{AND}, left => $op, right => $new_op) : $new_op;
        $left = $right;
    }
    return $op || $left;
}

sub _parse_expr_p {
    my ($self, $cur_prior) = @_;
    return $self->_parse_prefix if $cur_prior == PREF_PRIOR;
    return $self->_parse_cmp($cur_prior) if $cur_prior == CMP_PRIOR;
    my $root = $self->_parse_expr_p($cur_prior + 1);
    while($cur_prior == $self->_prior) {
        my $t = $self->{token};
        $self->_next_token;
        $root = CATS::Formal::Expressions::Binary->new(op => $t, left => $root, right => $self->_parse_expr_p($cur_prior + 1));
    }
    return $root;
}

sub _parse_expr {
    my ($self, $fd) = @_;
    $self->{fd} = $fd;
    $self->_next_token;
    my $r = $self->_parse_expr_p(1);
    $self->{fd} = undef;
    $r;
}

sub _parse_chars {
    my $self = shift;
    my $fd = shift;
    
    #FUUUUUUUUUUUUUUUUUU
    my $src = \$self->{src};
    my $p2 = '{.*?(?<!\\\\)}';
    $$src =~ /^\s*(!$p2|$p2)/;
    $self->_assert(!$1, "expected chars definition");
    my @chars = split //, $1;
    $$src = $';
    my $neg = $chars[0] eq '!';
    my @res = ($neg) x 255;
    shift @chars if $neg;
    shift @chars; #{
    pop @chars; #}
    my $i = 0;
    my $c = @chars;
    while ($i < $c){
        if ($chars[$i] eq '\\') {
            $self->_assert($i + 1 == $c, "expected charater after '\\'");
            my $ch = $chars[$i + 1];
            my @s = split //, '-}\\0123456789';
            $self->_assert((!grep $_ eq $ch, @s),
                           "expected one of charaters '-}\\0123456789' got $ch");
            ++$i;
            if ($ch =~ /\d/) {
                my $j = ord($ch) - ord('0');
                while($chars[$i + 1] =~ /\d/ && $j * 10 + ord($chars[$j + 1]) - ord('0') < 255){
                    $j = $j * 10 + ord($chars[++$i]) - ord('0');
                }
                $res[$j] = !$neg;
                ++$i;
            } else { 
                $res[ord($chars[++$i])] = !$neg;
                ++$i;
            }
        } elsif ($i > 0 && $chars[$i] eq '-'){
            $self->_assert($i + 1 == $c, "expected charater after '-'");
            my $a = ord($chars[$i - 1]);
            my $b = ord($chars[$i + 1]);
            for ($a .. $b){
                $res[$_] = !$neg;
            }
            $i += 2;
        } else {
            $res[ord($chars[$i++])] = !$neg;
        }
    }
    
    my $str = '';
    for my $i (0 .. $#res){
        $str .= chr($i) if $res[$i];
    }
    #ENDFUUUUUUUUUUUU
    
    $fd->{attributes}->{chars} = CATS::Formal::Expressions::String->new($str);
    $self->_next_token;
}

sub _parse_attrs {
    my ($self, $fd) = @_;
    my $need_next = 0;
    my $token = \$self->{token};
    while ($$token != TOKENS->{SEMICOLON} || $need_next) {
        if ($$token == TOKENS->{NAME}) {
            $self->_assert($fd->{name}, "duplicate attribute 'name'");
            $self->_next_token;
            $self->_expect('EQ');
            $self->_next_token;
            $self->_expect_identifier;
            $self->_assert($fd->{parent}->find_child($self->{token_str}),
                           "object with name '$self->{token_str}' already defined");
            $fd->{name} = $self->{token_str};
            $self->_next_token;
        } elsif ($$token == TOKENS->{CHARS}) {
            $self->_assert($fd->{attributes}->{chars}, "duplicate attribute 'chars'");
            $self->_next_token;
            $self->_expect('EQ');
            $self->_parse_chars($fd);
        } else {
            $self->_expect_identifier;
            $self->_assert($fd->{attributes}->{$self->{token_str}}, "duplicate attribute '$self->{token_str}'");
            my $attr = $self->{token_str};
            $self->_next_token;
            $self->_expect('EQ');
            my $expr = $self->_parse_expr($fd);
            $fd->{attributes}->{$attr} = $expr;
        }
        if ($$token == TOKENS->{COMMA}){
            $self->_next_token;
            $need_next = 1;
        } else {
            $need_next = 0;
        }
    }
    $self->_expect('SEMICOLON');
    $self->_next_token;
}

sub _parse_constraint {
    my $self = shift;
    $self->_assert(!@{$self->{curParent}->{children}}, "assert can't be the first element");
    my $last = $self->{curParent}->{children}->[-1];
    my $constraint = $self->_parse_expr($last);
    $last->add_constraint($constraint);
    $self->_expect('SEMICOLON');
    $self->_next_token;
}

sub _parse_obj {
    my $self = shift;
    my @types = (TOKENS->{INT}, TOKENS->{STRING}, TOKENS->{FLOAT}, TOKENS->{SEQ});
    if (grep $_ == $self->{token}, @types) {
        my $fd = CATS::Formal::Description->new({
            type => $self->{token},
            parent => $self->{curParent}
        });
        $self->_next_token;
        $self->_parse_attrs($fd);
        return $fd;
    } elsif ($self->{token} == TOKENS->{SENTINEL}){
        return $self->_parse_sentinel;
    } elsif ($self->{token} == TOKENS->{CONSTRAINT}) {
        $self->_parse_constraint;
        return undef;
    } elsif ($self->{token} == TOKENS->{NEWLINE}) {
        $self->_next_token;
        $self->_next_token if $self->{token} == TOKENS->{SEMICOLON};
        return CATS::Formal::Description->new({
            type => TOKENS->{NEWLINE},
            parent => $self->{curParent}
        });
    } else {
        $self->error("expected 'int'|'string'|'float'|'seq'|'newline' got $self->{token_str}");
    }
    
}

sub _parse_seq {
    my $self = shift;
    my $obj = $self->_parse_obj;
    return undef unless $obj;
    $self->{curParent} = $obj;
    my $t = $obj->{type};
    if ($t == FD_TYPES->{SEQ} || $t == FD_TYPES->{SENTINEL}) {
        $self->_parse_seq while $self->{token} != TOKENS->{END};
        $self->_next_token;
        $self->_next_token if $self->{token} == TOKENS->{SEMICOLON};
    }
    $self->{curParent} = $obj->{parent};
}

sub _parse_params {
    my ($self) = @_;
    while ($self->{token} == TOKENS->{SHARP}){
        $self->_next_token;
        $self->_expect_identifier;
        my $parameter = $self->{token_str};
        $self->_next_token;
        $self->_expect('EQ');
        my $expr = $self->_parse_expr();
        $self->{curParent}->{attributes}->{$parameter} = $expr;
    }
}

sub _parse_input {
    my $self = shift;
    my $fd = CATS::Formal::Description->new ({type => FD_TYPES->{INPUT}, parent => $self->{curParent}});
    $self->{curParent} = $fd;
    $self->_parse_params;
    while ($self->{token} != TOKENS->{EOF}) {
        $self->_parse_seq;
    }
    
    $self->{curParent} = $fd->{parent};
    
}

sub _parse_output {
    my ($self, $root) = @_;
    $self->_next_token;
    my $fd = CATS::Formal::Description->new ({type => FD_TYPES->{OUTPUT}, parent => $root});
    $self->{curParent} = $fd;
    $self->_parse_params;
    while ($self->{token} != TOKENS->{EOF}) {
        $self->_parse_seq;
    }
    
    $self->{curParent} = $fd->{parent};
    return $root;
}

sub _parse_fd {
    my $self = shift;
    my $fd = CATS::Formal::Description->new({type => FD_TYPES->{ROOT}});
    $self->{curParent} = $fd;
    $self->_parse_input;
    $self->{curParent} = $fd->{parent};
    $fd;
}

sub error {
    $_[0]->{error} = $_[1];
    die $_[1];
}



1;
