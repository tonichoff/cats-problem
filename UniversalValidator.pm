package CATS::Formal::UniversalValidator;
use strict;
use warnings;

use File::Slurp;

use Constants;
use Expressions;
BEGIN {CATS::Formal::Constants->import()};

sub assert {
    CATS::Formal::Error::assert(@_);
}

sub new {
    bless {}, $_[0];
}

sub validate {
    my ($self, $root, $is_files, %ioa) = @_;
    my @keys = qw(INPUT ANSWER OUTPUT);
    $self->{cur} = {};
    foreach my $k (@keys){
        my $fd = $root->find_child($k);
        my $text = $ioa{$k};
        if ($is_files) {
            $text = read_file($text);
        }
        
        $self->validate_top($fd, $text);
    }
}

sub validate_top {
    my ($self, $fd, $text) = @_;
    $self->{pos} = 0;
    $self->{col} = 0;
    $self->{row} = 0;
    $self->{data} = $text;
    $self->{params} = {};
    %{$self->{params}} = %{$fd->{attributes}};
    unless ($self->{params}->{strict}) {
        $self->{params}->{strict} = CATS::Formal::Expressions::Integer->new(1); 
    }
    
    $self->read_token;
    $self->validate_record($fd);
}

sub read_space {
    my ($self) = @_;
    $self->{data} =~ /^( |\t)/;
    $self->{data} = $';
}

sub read_newline {
    my ($self) = @_;
    $self->{data} =~ /^(\n)/;
    $self->{data} = $';
}

sub read_spaces {
    my ($self) = @_;
    $self->{data} =~ /^(\s*)/;
    $self->{data} = $';
}

sub read_token {
    my ($self) = @_;
    unless ($self->{params}->{strict}) {
        $self->read_spaces;
    }
    
    if ($self->{data} =~ /^(\S+)/) {
        $self->{token} = $1;
        $self->{data} = $';
        return $self->{token};
    }
    return $self->{token} = '';
}

sub get_and_read_token {
    my ($self) = @_;
    my $res = $self->{token};
    $self->read_token;
    return $res;
}

sub to_int {
    my ($self, $token) = @_;
    my $p = '-?\d+';
    if ($token =~ /^$p$/) {
        return CATS::Formal::Expressions::Integer->new($token);
    }
    CATS::Formal::Error::set("integer expected but '$token' given");
}

sub to_float {
    my ($self, $token) = @_;
    my $p = '-?[0-9]+(\.[0-9]+([eE][-+]?[0-9]+)?)?';
    if ($token =~ /^$p$/) {
        return CATS::Formal::Expressions::Float->new($token);
    }
    CATS::Formal::Error::set("float expected but '$token' given");
}

sub to_string {
    CATS::Formal::Expressions::String->new($_[1]);
}

sub check_range {
    my ($self, $fd, $val, $token, $type, $range, $v) = @_;
    if (defined $range) {
        my $r = $range->evaluate($v);
        if ($r->is_int) {
            assert($r != $val, "expected $type equal to '$r' but '$token' given");
        } elsif ($r->is_array) {
            my $a = $r->[0];
            my $b = $r->[1];
            assert(!($a <= $val && $val <= $b), "expected $type in range from $a to $b but '$token' given");
        } else {
            die "BUG";
        }
    }
}

sub validate_int {
    my ($self, $fd) = @_;
    my $token = $self->get_and_read_token;
    my $int = $self->to_int($token);
    my $val = {
        val => $int,
        parent => $self->{cur},
        fd => $fd,
    };
    my $range = $fd->{attributes}->{range};
    $self->check_range($fd, $int, $token, 'integer', $range, $val);
    $self->{newline} = 0;
    return $val;
}

sub validate_float {
    my ($self, $fd) = @_;
    my $token = $self->get_and_read_token;
    my $float = $self->to_float($token);
    my $val = {
        val => $float,
        parent => $self->{cur},
        fd => $fd,
    };
    my $range = $fd->{attributes}->{range};
    $self->check_range($fd, $float, $token, 'float', $range, $val);
    my $digits = $fd->{attributes}->{digits};
    if (defined $digits) {
        my $count = length(($token =~ /\.(.*)/)[0]);
        assert (!($token =~ /^-?[0-9]+\.[0-9]+$/), "can't use digits attribute with float in extended form");
        my $e = $digits->evaluate($val);
        if ($e->is_int) {
            my $e = $digits->evaluate($val);
            assert($$e != $count,
                "expected float with $e charaters after decimal point " .
                "but got '$token' ($count)"
            );
        } elsif ($e->is_array) {
            my $a = $e->[0];
            my $b = $e->[1];
            assert(!($$a <= $count && $count <= $$b),
                "expected float with count of characters after decimal point " .
                "in range from $a to $b but got '$token' ($count)"
            );
        } else {
            die "BUG";
        }
    }
    $self->{newline} = 0;
    return $val;
}

sub validate_string {
    my ($self, $fd) = @_;
    my $token = $self->get_and_read_token;
    my $string = $self->to_string($token);
    my $val = {
        val => $string,
        parent => $self->{cur},
        fd => $fd,
    };
    my $lenrange = $fd->{attributes}->{lenrange};
    if (defined $lenrange) {
        my $len = CATS::Formal::Expressions::Integer->new(length($token));
        $self->check_range($fd, $len, $token, 'string with length', $lenrange, $val);
    }
    my $chars = $fd->{attributes}->{chars};
    if (defined $chars) {
        my @letters = split '', $token;
        foreach (@letters) {
            assert(index($$chars, $_) == -1,
                "expected string consisting of '$chars' but got '$token' ($_)"       
            );
        }
    }
    $self->{newline} = 0;
    return $val;
}

sub validate_seq {
    my ($self, $fd) = @_;
    my $val = {
        parent => $self->{cur},
        fd => $fd,
        children => [],
        val  => CATS::Formal::Expressions::Array->new([])
    };
    $self->{cur} = $val;
    my $length = $fd->{attributes}->{length};
    if (defined $length) {
        my $len_val = $length->evaluate($val);
        for (my $v = 0; $v < $$len_val; ++$v){
            my $cv = $self->validate_record($fd);
            push @{$val->{children}}, $cv;            
            push @{$val->{val}}, $cv->{val}; 
            if ($v + 1 != $$len_val && !$self->{newline}) {
                $self->{need_space} = 1;
            }
        }
    } else {
        while ($self->peek_token ne '') {
            my $cv = $self->validate_record($fd);
            push @{$val->{children}}, $cv;            
            push @{$val->{val}}, $cv->{val};
            if ($self->peek_token ne '' && !$self->{newline}) {
                $self->{need_space} = 1;
            }
        } 
    }
    $self->{cur} = $val->{parent};
    return $val;
}

sub validate_record {
    my ($self, $record) = @_;
    my $val = {
        parent => $self->{cur},
        fd => $record,
        children => [],
        val  => CATS::Formal::Expressions::Record->new([])
    };
    $self->{cur} = $val;
    foreach my $child (@{$record->{children}}){
        my $v = $self->validate_obj($child);
        if ($v->{val}) {
            push @{$val->{children}}, $v;
            push @{$val->{val}}, {fd => $v->{fd}, val => $v->{val}};
        }
        if ($child != $record->{children}->[-1] && !$self->{newline}) {
            $self->read_space;
        }
    }
    $self->{cur} = $val->{parent};
    return $val;
}

sub validate_newline {
    my ($self, $fd) = @_;
    $self->read_newline;
    $self->get_and_read_token;
    $self->{newline} = 1;
    return {fd => $fd, parent => $self->{cur}, val=>''};
sub validate_constraints {
    my ($self, $fd, $val) = @_;
    foreach my $c (@{$fd->{constraints}}){
        my $r = $c->evaluate($val);
        unless ($r) {
            my $s = $c->stringify;
            CATS::Formal::Error::set(
                "constraint '$s' failed"
            );   
        }
    }
}

sub validate_obj {
    my ($self, $fd) = @_;
    my %validators = (
        FD_TYPES()->{INT}     => \&validate_int,
        FD_TYPES()->{FLOAT}   => \&validate_float,
        FD_TYPES()->{STRING}  => \&validate_string,
        FD_TYPES()->{SEQ}     => \&validate_seq,
        FD_TYPES()->{RECORD}  => \&validate_record,
        FD_TYPES()->{NEWLINE} => \&validate_newline,
    );
    my $validator = $validators{$fd->{type}};
    my $val = $self->$validator($fd);
    $self->validate_constraints($fd, $val);
    return $val;
}

1;