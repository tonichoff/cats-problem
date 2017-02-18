package CATS::Problem::ImportSource::Local;

use strict;
use warnings;
use base qw(CATS::Problem::ImportSource::Base);

sub new
{
    my ($class, %opts) = @_;
    $opts{modulesdir} or die 'You must specify modules folder';
    $opts{id_counter} or $opts{id_counter} = 0;
    bless \%opts => $class;
}

sub get_source
{
    my ($self, $guid) = @_;
    my $source = CATS::SourceManager::load($guid, $self->{modulesdir});
    ($source->{id}, $source->{stype});
}

sub get_guids
{
    my ($self, $guid) = @_;
    CATS::SourceManager::get_guids_by_regexp($guid, $self->{modulesdir});
}

sub get_sources_info
{
    my ($self, $sources) = @_;
    $sources and @$sources or return ();

    map CATS::SourceManager::load($_->{guid}, $self->{modulesdir}), @$sources;
}

sub get_new_id { $_[0]->{id_counter}++ . ($_[2] // '') }

1;
