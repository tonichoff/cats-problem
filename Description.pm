package CATS::Formal::Description;
use strict;
use warnings;

use BaseObj;
use Constants;
use parent -norequire, 'CATS::Formal::BaseObj';

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
    my $res = ' ' x $deep . "<$t $a>\n";
    foreach my $child (@{$self->{children}}){
        $res .= $child->stringify($deep + 1);
    }
    return $res . ' ' x $deep . "<$t/>\n";
}

sub find {
    my ($self, $name) = @_;
    my $cur = $self;
    my $from_output = 0;
    while ($cur) {
        if ($from_output && $cur->{type} == CATS::Formal::Constants::FD_TYPES->{ROOT}) {
            $from_output = 0;
            $cur = $cur->find_child_by_type(CATS::Formal::Constants::FD_TYPES->{INPUT});
            return undef unless $cur;
        }
        
        return $cur if $cur->{name} && $cur->{name} eq $name;
        my $child = $cur->find_child($name);
        return $child if $child;
        if ($cur->{type} == CATS::Formal::Constants::FD_TYPES->{OUTPUT}) {
            $from_output = 1;
        }
        
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

1;