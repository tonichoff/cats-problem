package Logger;

#use Carp;
sub new { bless { notes => [], warnings => [] }, $_[0]; }
sub note { push @{$_[0]->{notes}}, $_[1] }
sub warning { push @{$_[0]->{warnings}}, $_[1] }
sub error { die $_[1] }

package ParserMockup;

use strict;
use warnings;

use File::Spec;
use FindBin;

use lib '..';

use CATS::Problem::ImportSource::Local;
use CATS::Problem::Source::Base;
use CATS::Problem::Parser;

sub make {
    my ($data, $desc) = @_;
    CATS::Problem::Parser->new(
        source => CATS::Problem::Source::Mockup->new(data => $data, logger => Logger->new),
        import_source => CATS::Problem::ImportSource::Local->new(
            modulesdir => File::Spec->catdir($FindBin::Bin, 'import')),
        id_gen => sub { $_[1] },
        problem_desc => { %{ $desc || {} } },
    );
}

1;
