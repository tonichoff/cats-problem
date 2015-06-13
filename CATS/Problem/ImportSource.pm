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

sub get_source
{
    die 'Method ImportSource::Local::get_source not implement yet';
}

sub get_guids
{
    die 'Method ImportSource::Local::get_guids not implement yet';
}

sub get_sources_info
{
    die 'Method ImportSource::Local::get_sources_info not implement yet';
}


1;
