package Logger;
sub new { bless {}, $_[0]; }
sub note {}
sub warning {}
sub error { die $_[1] }

package main;

use strict;
use warnings;

use lib '..';

use Test::More tests => 6;
use Test::Exception;

use CATS::Problem::ImportSource;
use CATS::Problem::Source::Base;
use CATS::Problem::Parser;

sub parse
{
    my ($data, $desc) = @_;
    my $parser = CATS::Problem::Parser->new(
        source => CATS::Problem::Source::Mockup->new(data => $data, logger => Logger->new),
        import_source => CATS::Problem::ImportSource::Local->new(modulesdir => '.'),
        id_gen => sub { 1 },
        problem_desc => { %{ $desc || {} } },
    )->parse;
}

sub wrap_xml { qq~<?xml version="1.0" encoding="Utf-8"?><CATS version="1.0">$_[0]</CATS>~ }

sub wrap_problem {
    wrap_xml(qq~
<Problem title="Title" lang="en" tlimit="5" mlimit="6" inputFile="input.txt" outputFile="output.txt">
$_[0]
</Problem>
~)
}

subtest 'trivial errors', sub {
    plan tests => 3;
    throws_ok { parse({ 'text.x' => 'zzz' }); } qr/xml not found/, 'no xml';
    throws_ok { parse({ 'text.xml' => 'zzz' }); } qr/error/, 'bad xml';
    TODO: {
        local $TODO = 'Should validate on end_CATS, not end_Problem';
        throws_ok { parse({ 'text.xml' => wrap_xml('') }) } qr/error/, 'missing Problem';
    }
};

subtest 'header', sub {
    plan tests => 7;
    my $d = parse({
        'test.xml' => wrap_xml(q~
<Problem title="Title" lang="en" author="A. Uthor" tlimit="5" mlimit="6" inputFile="input.txt" outputFile="output.txt">
<Checker src="checker.pp"/>
</Problem>~),
    'checker.pp' => 'begin end.',
    })->{description};
    is $d->{title}, 'Title', 'title';
    is $d->{author}, 'A. Uthor', 'author';
    is $d->{lang}, 'en', 'lang';
    is $d->{time_limit}, 5, 'time';
    is $d->{memory_limit}, 6, 'memory';
    is $d->{input_file}, 'input.txt', 'input';
    is $d->{output_file}, 'output.txt', 'output';
};

subtest 'missing', sub {
    plan tests => 5;
    throws_ok { parse({
        'test.xml' => wrap_xml(q~
<Problem title="Title" tlimit="5" mlimit="6" inputFile="input.txt" outputFile="output.txt"/>~),
    }) } qr/lang/, 'missing lang';
    throws_ok { parse({
        'test.xml' => wrap_xml(q~
<Problem title="Title" lang="en" mlimit="6" inputFile="input.txt" outputFile="output.txt"/>~),
    }) } qr/tlimit/, 'missing time limit';
    is parse({
        'test.xml' => wrap_xml(q~
<Problem title="Title" lang="en" tlimit="5" inputFile="input.txt" outputFile="output.txt">
<Checker src="checker.pp"/>
</Problem>~),
        'checker.pp' => 'begin end.',
    })->{description}->{memory_limit}, 200, 'default memory limit';
    throws_ok { parse({
        'test.xml' => wrap_xml(q~
<Problem title="Title" lang="en" tlimit="5" mlimit="6" inputFile="input.txt"/>~),
    }) } qr/outputFile/, 'missing output file';
    throws_ok { parse({
        'test.xml' => wrap_xml(q~
<Problem title="Title" lang="en" tlimit="5" mlimit="6" inputFile="input.txt" outputFile="output.txt"/>~),
    }) } qr/checker/, 'missing checker';
};

subtest 'rename', sub {
    plan tests => 2;
    throws_ok { parse({
        'test.xml' => wrap_xml(q~
<Problem title="New Title" lang="en" tlimit="5" mlimit="6" inputFile="input.txt" outputFile="output.txt"/>~),
    }, { old_title => 'Old Title' }) } qr/rename/, 'unexpected rename';
    is parse({
        'test.xml' => wrap_xml(q~
<Problem title="Old Title" lang="en" tlimit="5" mlimit="6" inputFile="input.txt" outputFile="output.txt">
<Checker src="checker.pp"/>
</Problem>~),
        'checker.pp' => 'begin end.',
    }, { old_title => 'Old Title' })->{description}->{title}, 'Old Title', 'expected rename';
};

subtest 'sources', sub {
    plan tests => 2;
    is parse({
        'test.xml' => wrap_problem(q~<Checker src="checker.pp"/>~),
        'checker.pp' => 'checker1',
    })->{checker}->{src}, 'checker1', 'checker';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Checker src="chk.pp"/>~),
    }) } qr/checker.*chk\.pp/, 'no checker';
};

subtest 'text', sub {
    plan tests => 10;
    my $p = parse({
        'test.xml' => wrap_problem(q~
<Checker src="checker.pp"/>
<ProblemStatement>problem
statement</ProblemStatement>
<ProblemConstraints>$N = 0$</ProblemConstraints>
<InputFormat>x, y, z</InputFormat>
<OutputFormat>single number</OutputFormat>
<Explanation>easy</Explanation>~),
        'checker.pp' => 'z',
    });
    is $p->{statement}, "problem\nstatement", 'statement';
    is $p->{constraints}, '$N = 0$', 'constraints';
    is $p->{input_format}, 'x, y, z', 'input';
    is $p->{output_format}, 'single number', 'output';
    is $p->{explanation}, 'easy', 'explanation';

    my $p1 = parse({
        'test.xml' => wrap_problem(q~
<Checker src="checker.pp"/>
<ProblemStatement>outside<b  class="  z  " > inside </b></ProblemStatement>
<ProblemConstraints>before<include src="incl"/>after</ProblemConstraints>~),
        'checker.pp' => 'z',
        'incl' => 'included'
    });
    is $p1->{statement}, 'outside<b class="  z  "> inside </b>', 'tag reconstruction';
    is $p1->{constraints}, 'beforeincludedafter', 'include';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<ZZZ></ZZZ>~),
    }) } qr/ZZZ/, 'unknown tag';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<ProblemStatement><include/></ProblemStatement>
<Checker src="checker.pp"/>~),
        'checker.pp' => 'z',
    }) } qr/include/, 'no incude src';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<ProblemStatement><include src="qqq"/></ProblemStatement>
<Checker src="checker.pp"/>~),
        'checker.pp' => 'z',
    }) } qr/qqq/, 'bad incude src';
};
