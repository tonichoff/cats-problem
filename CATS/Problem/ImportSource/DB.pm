package CATS::Problem::ImportSource::DB;

use strict;
use warnings;
use CATS::DB;
use base qw(CATS::Problem::ImportSource::Base);

sub get_source {
    my ($self, $guid) = @_;
    $dbh->selectrow_array(q~
        SELECT psl.id, psl.stype FROM problem_sources_local psl WHERE psl.guid = ?~, undef,
        $guid);
}

sub get_guids {
    my ($self, $guid) = @_;
    $guid =~ s/%/\\%/g;
    $guid =~ s/\*/%/g;
    @{$dbh->selectcol_arrayref(q~
        SELECT guid FROM problem_sources_local WHERE guid LIKE ? ESCAPE '\\'~, undef,
        $guid)};
}

sub get_sources_info {
    my ($self, $sources) = @_;
    $sources and @$sources or return ();

    my $param_str = '?' . ', ?' x scalar @$sources - 1;
    @{$dbh->selectall_arrayref(qq~
        SELECT DISTINCT psl.*, dd.code FROM problem_sources_local psl
            INNER JOIN default_de dd ON dd.id = psl.de_id
        WHERE psl.guid IN ($param_str)~, { Slice => {} },
        map { $_->{guid} } @$sources)};
}

sub get_new_id { CATS::DB::new_id(@_) }

1;
