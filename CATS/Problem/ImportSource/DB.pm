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

sub get_new_id { CATS::DB::new_id(@_) }

1;
