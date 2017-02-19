package CATS::Formal::Description;
use strict;
use warnings;

use CATS::Formal::Expressions;
use CATS::Formal::Constants;

use parent 'CATS::Formal::BaseObj';

sub is_description {1;}

sub new {
    my $class = shift;
    my $arg = shift;
    my $self = bless {}, $class;
    $self->{name} = $arg->{name};
    $self->{type} = $arg->{type};
    $self->{parent} = $arg->{parent};
    $self->{children} = [];
    $self->{constraints} = [];
    $self->{attributes} = {};
    $self->{parent}->add_child($self) if $self->{parent};
    
    return $self;
}

sub stringify {
    my $self = shift;
    my $deep = 0;
    if (@_) {
        $deep = shift;
    }
    
    my $a = $self->{name} ? 'name=' . $self->{name}.' ' : '';
    foreach (keys %{$self->{attributes}}){
        my $e = $self->{attributes}->{$_}->stringify;
        $a .= "$_=( $e ) ";
    }
    my $t = CATS::Formal::Constants::RFD_TYPES->{$self->{type}};
    my $res = '  ' x $deep . "<$t $a>\n";
    foreach my $child (@{$self->{children}}){
        $res .= $child->stringify($deep + 1);
    }
    return $res . '  ' x $deep . "</$t>\n";
}

sub find {
    my ($self, $name) = @_;
    my $cur = $self->{parent};
    while ($cur) {
        my $child = $cur->find_child($name);
        return $child if $child;        
        $cur = $cur->{parent};        
    }
    return $cur;    
}

sub add_child {
    push @{$_[0]->{children}}, $_[1];
}

sub find_child {
    my ($self, $arg) = @_;
    foreach (@{$self->{children}}) {
        return $_ if $_->{name} && $arg eq $_->{name};
    }
    return undef;
}

sub find_child_by_type {
    my ($self, $type) = @_;
    foreach (@{$self->{children}}) {
        return $_ if $type == $_->{type};
    }
    return undef;
}

sub add_constraint {
    push @{$_[0]->{constraints}}, $_[1];
}

sub to_expr_type {
    my ($self) = @_;
    my %fd_to_expr = (
        FD_TYPES()->{INT} => 'CATS::Formal::Expressions::Integer',
        FD_TYPES()->{STRING} => 'CATS::Formal::Expressions::String',
        FD_TYPES()->{FLOAT} => 'CATS::Formal::Expressions::Float',
        FD_TYPES()->{SEQ} => 'CATS::Formal::Expressions::Array',
        FD_TYPES()->{RECORD} => 'CATS::Formal::Expressions::Record',
    );
    my $type = $fd_to_expr{$self->{type}};
    unless ($type){
        my $t = RFD_TYPES()->{$self->{type}}; 
        CATS::Formal::Error::set(
            "unable to convert object of type '$t' to expression type"
        );
    }
    return $type;
}

sub find_self_val {
    my ($self, $val) = @_;
    for (my $cur = $val; $cur; $cur = $cur->{parent}) {
        #if not seq record
        if ($cur->{fd} == $self && $cur->{fd} != $cur->{parent}->{fd}) {
            return $cur;
        }
        #if seq
        $cur->{fd}->{type} == FD_TYPES()->{SEQ} &&
            $cur->{parent}->{fd} != $cur->{fd}  &&
            next;
        
        foreach my $c (@{$cur->{children}}){
            return $c if $c->{fd} == $self;
        }        
    }
    return undef;
}

1;