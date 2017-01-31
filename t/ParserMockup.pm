package Logger;

#use Carp;
sub new { bless {}, $_[0]; }
sub note {}
sub warning {}
sub error { die $_[1] }

package ParserMockup;

use strict;
use warnings;

use lib '..';

use CATS::Problem::ImportSource;
use CATS::Problem::Source::Base;
use CATS::Problem::Parser;

sub make
{
    my ($data, $desc) = @_;
    CATS::Problem::Parser->new(
        source => CATS::Problem::Source::Mockup->new(data => $data, logger => Logger->new),
        import_source => CATS::Problem::ImportSource::Local->new(modulesdir => '.'),
        id_gen => sub { $_[1] },
        problem_desc => { %{ $desc || {} } },
    );
}

1;
