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


package CATS::Problem::ImportSource::DB;

use strict;
use warnings;
use CATS::DB;
use base qw(CATS::Problem::ImportSource::Base);

sub get_source
{
    my ($self, $guid) = @_;
    $dbh->selectrow_array(qq~SELECT id, stype FROM problem_sources WHERE guid = ?~, undef, $guid);
}

sub get_guids
{
    my ($self, $guid) = @_;
    $guid =~ s/%/\\%/g;
    $guid =~ s/\*/%/g;
    @{$dbh->selectcol_arrayref(qq~SELECT guid FROM problem_sources WHERE guid LIKE ? ESCAPE '\\'~, undef, $guid)};
}

sub get_sources_info
{
    my ($self, $sources) = @_;
    $sources and @$sources or return ();

    my $param_str = '?' . ', ?' x scalar @$sources - 1;
    @{$dbh->selectall_arrayref(qq~
        SELECT DISTINCT ps.*, dd.code FROM problem_sources ps
            INNER JOIN default_de dd ON dd.id = ps.de_id
        WHERE ps.guid IN ($param_str) AND ps.id = (SELECT MAX(ps1.id) FROM problem_sources ps1 WHERE ps1.guid = ps.guid)~, { Slice => {} },
        map { $_->{guid} } @$sources)};
}


package CATS::Problem::ImportSource::Local;

use strict;
use warnings;
use base qw(CATS::Problem::ImportSource::Base);

sub new
{
    my ($class, %opts) = @_;
    $opts{modulesdir} or die 'You must specify modules folder';
    bless \%opts => $class;
}

sub get_source
{
    my ($self, $guid) = @_;
    my $source = CATS::SourceManager::load($guid, $self->{modulesdir});
    $source->{id} && $source->{stype} ? ($source->{id}, $source->{stype}) : (undef, undef);
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

    use Data::Dumper;
    my @result = ();
    push @result, CATS::SourceManager::load($_->{guid}, $self->{modulesdir}) for @$sources;
    @result;
}


1;
