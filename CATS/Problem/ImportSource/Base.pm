package CATS::Problem::ImportSource::Base;

use strict;
use warnings;

sub new
{
    my ($class) = shift;
    my $self = { @_ };
    bless $self, $class;
    $self;
}

sub get_source { (undef, undef); }

sub get_guids { (); }

sub get_sources_info { (); }

sub get_new_id { 0 }

1;
