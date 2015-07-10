package Logger;
sub new { bless {}, $_[0]; }
sub note {}
sub warning {}
sub error { die $_[1] }

package main;

use strict;
use warnings;

use lib '..';

use Test::More tests => 2;
use Test::Exception;

use CATS::Problem::ImportSource;
use CATS::Problem::Source::Base;
use CATS::Problem::Parser;

sub parse
{
    my ($data) = @_;
    my $parser = CATS::Problem::Parser->new(
        source => CATS::Problem::Source::Mockup->new(data => $data, logger => Logger->new),
        import_source => CATS::Problem::ImportSource::Local->new(modulesdir => '.'),
        id_gen => sub { 1 },
        problem_desc => {},
    )->parse;
}

subtest 'trivial errors', sub {
    throws_ok { parse({'text.x' => 'zzz'}); } qr/xml not found/, 'no xml';
    throws_ok { parse({'text.xml' => 'zzz'}); } qr/error/, 'bad xml';
    TODO: {
        local $TODO = 'Should validate on end_CATS, not end_Problem';
        throws_ok { parse({'text.xml' => '<?xml version="1.0" encoding="Utf-8"?>
<CATS version="1.0"></CATS>'});
        } qr/error/, 'missing Problem';
    }
};

subtest 'Trivial', sub {
    my $d = parse({
        'test.xml' => '<?xml version="1.0" encoding="Utf-8"?>
<CATS version="1.0">
<Problem title="Title" lang="en" author="A. Uthor" tlimit="5" mlimit="6"
    inputFile="input.txt" outputFile="output.txt">
<Checker src="checker.pp"/>
</Problem></CATS>',
    'checker.pp' => 'begin end.',
    })->{description};
    is $d->{title}, 'Title';
    is $d->{author}, 'A. Uthor';
    is $d->{lang}, 'en';
    is $d->{time_limit}, 5;
    is $d->{memory_limit}, 6;
    is $d->{input_file}, 'input.txt';
    is $d->{output_file}, 'output.txt';
};
