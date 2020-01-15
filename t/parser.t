package main;

use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More tests => 19;
use Test::Exception;

use lib File::Spec->catdir($FindBin::Bin, '..');
use lib $FindBin::Bin;

use CATS::Problem::Parser;
use ParserMockup;

sub parse { ParserMockup::make(@_)->parse }

sub wrap_xml { qq~<?xml version="1.0" encoding="Utf-8"?><CATS version="1.0">$_[0]</CATS>~ }

sub wrap_problem {
    wrap_xml(qq~
<Problem title="Title" lang="en" tlimit="5" mlimit="6" inputFile="input.txt" outputFile="output.txt">
$_[0]
</Problem>
~)
}

# Work around older Test::More.
BEGIN { if (!main->can('subtest')) { *subtest = sub ($&) { $_[1]->(); }; *plan = sub {}; } }

subtest 'trivial errors', sub {
    plan tests => 5;
    throws_ok { parse({ 'text.x' => 'zzz' }); } qr/xml not found/, 'no xml';
    throws_ok { parse({ 'text.xml' => 'zzz' }); } qr/error/, 'bad xml';
    throws_ok { parse({
        'text.xml' => '<?xml version="1.0" encoding="Utf-8"?><ZZZ/>',
    }); } qr/ZZZ/, 'no CATS 1';
    throws_ok { parse({
        'text.xml' => '<?xml version="1.0" encoding="Utf-8"?><Problem/>',
    }); } qr/Problem.+CATS/, 'no CATS 2';
    TODO: {
        local $TODO = 'Should validate on end_CATS, not end_Problem';
        throws_ok { parse({ 'text.xml' => wrap_xml('') }) } qr/error/, 'missing Problem';
    }
};

subtest 'header', sub {
    plan tests => 11;
    my $d = parse({
        'test.xml' => wrap_xml(q~
<Problem title="Title" lang="en" author="A. Uthor" tlimit="5" mlimit="6" wlimit="100B"
    saveOutputPrefix="100B" saveInputPrefix="200B" saveAnswerPrefix="300B" inputFile="input.txt" outputFile="output.txt">
<Checker src="checker.pp"/>
</Problem>~),
    'checker.pp' => 'begin end.',
    })->{description};
    is $d->{title}, 'Title', 'title';
    is $d->{author}, 'A. Uthor', 'author';
    is $d->{lang}, 'en', 'lang';
    is $d->{time_limit}, 5, 'time';
    is $d->{memory_limit}, 6, 'memory';
    is $d->{save_output_prefix}, 100, 'saveOutputPrefix';
    is $d->{save_input_prefix}, 200, 'saveInputPrefix';
    is $d->{save_answer_prefix}, 300, 'saveAnswerPrefix';
    is $d->{write_limit}, 100, 'write';
    is $d->{input_file}, 'input.txt', 'input';
    is $d->{output_file}, 'output.txt', 'output';
};

subtest 'missing', sub {
    plan tests => 6;
    throws_ok { parse({
        'test.xml' => wrap_xml(q~
<Problem title="" lang="en" tlimit="5" mlimit="6" inputFile="input.txt" outputFile="output.txt"/>~),
    }) } qr/title/, 'empty title';
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
    plan tests => 8;

    is parse({
        'test.xml' => wrap_problem(q~<Checker src="checker.pp"/>~),
        'checker.pp' => 'checker1',
    })->{checker}->{src}, 'checker1', 'checker';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Checker src="chk.pp"/>~),
    }) } qr/checker.*chk\.pp/, 'no checker';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Checker src="chk.pp"/>
<Checker src="chk.pp"/>
~),
        'chk.pp' => 'checker1',
    }) } qr/checker/, 'duplicate checker';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Solution/>~),
    }) } qr/Solution.src/, 'no solution src';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Solution src="zzz"/>~),
    }) } qr/Solution.name/, 'no solution nme';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Checker src="chk.pp"/>
<Solution name="sol1" src="sol"/>
~),
        'chk.pp' => 'checker1',
    }) } qr/sol/, 'missing solution';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Checker src="chk.pp"/>
<Solution name="sol1" src="chk.pp"/>
<Solution name="sol1" src="chk.pp"/>
~),
        'chk.pp' => 'checker1',
    }) } qr/sol1/, 'duplicate solution';

    my $sols = parse({
        'test.xml' => wrap_problem(q~
<Checker src="chk.pp"/>
<Solution name="sol1" src="chk.pp"/>
<Solution name="sol2" src="chk.pp"/>
~),
        'chk.pp' => 'checker1',
    })->{solutions};
    is_deeply [ map $_->{path}, @$sols ], [ 'chk.pp', 'chk.pp' ], 'two solutions';
};

subtest 'import', sub {
    plan tests => 3;
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Import/>~),
    }) } qr/Import.guid/, 'Import without guid';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Import guid="nonexisting"/>~),
    }) } qr/nonexisting/, 'non-existing guid';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Import guid="empty" type="yyy"/>~),
    }) } qr/type.*'yyy'/, 'incorrect type';
};

subtest 'text', sub {
    plan tests => 12;
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

    my $p2 = parse({
        'test.xml' => wrap_problem(q~
<Checker src="checker.pp"/>
<ProblemStatement>&amp;&lt;&gt;&quot;</ProblemStatement>~),
        'checker.pp' => 'z',
    });
    is $p2->{statement}, '&amp;&lt;&gt;&quot;', 'xml characters';

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

    throws_ok { parse({
        'text.xml' => wrap_problem(q~
<ProblemStatement><ProblemConstraints></ProblemConstraints></ProblemStatement>~),
    }); } qr/Unexpected.*ProblemConstraints/, 'ProblemConstraints inside ProblemStatement';
};

subtest 'picture-attachment', sub {
    plan tests => 19;
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<ProblemStatement><img/></ProblemStatement>~),
    }) } qr/picture/i, 'img without picture';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<ProblemStatement><img picture="qqq"/></ProblemStatement>~),
    }) } qr/qqq/, 'img with bad picture';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<ProblemStatement><a attachment="zzz"/></ProblemStatement>~),
    }) } qr/zzz/, 'a with bad attachment';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<ProblemStatement><object attachment="zzz"/></ProblemStatement>~),
    }) } qr/zzz/, 'object with bad attachment';

    for my $tag (qw(Picture Attachment)) {
        throws_ok { parse({
            'test.xml' => wrap_problem(qq~<$tag/>~),
        }) } qr/src/, "$tag without src";

        throws_ok { parse({
            'test.xml' => wrap_problem(qq~<$tag src="test"/>~),
        }) } qr/name/, "$tag without name";

        throws_ok { parse({
            'test.xml' => wrap_problem(qq~<$tag src="xxxx" name="yyyy"/>~),
        }) } qr/xxxx/, "$tag with bad src";
    }

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Picture src="p1" name="p1" />~),
        'p1' => 'p1data',
    }) } qr/extension/, 'bad picture extension';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Attachment src="a1.txt" name="a1" />
<ProblemStatement><img picture="a1"/></ProblemStatement>
~),
        'a1.txt' => 'a1data',
    }) } qr/a1/, 'img references attachment';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Picture src="p1.txt" name="p1" />
<ProblemStatement><a attachment="p1"/></ProblemStatement>
~),
        'p1.txt' => 'p1data',
    }) } qr/p1/, 'a references picture';

    my $p = parse({
        'test.xml' => wrap_problem(q~
<Picture src="p1.img" name="p1" />
<Attachment src="a1.txt" name="a1" />
<ProblemStatement>
text <img picture="p1"/> <a attchment="a1"/>
</ProblemStatement>
<Checker src="checker.pp"/>
~),
        'checker.pp' => 'z',
        'p1.img' => 'p1data',
        'a1.txt' => 'a1data',
    });

    is scalar @{$p->{pictures}}, 1, 'pictures count';
    is $p->{pictures}->[0]->{name}, 'p1', 'picture 1 name';
    is $p->{pictures}->[0]->{src}, 'p1data', 'picture 1 data';
    is scalar @{$p->{attachments}}, 1, 'attachments count';
    is $p->{attachments}->[0]->{name}, 'a1', 'attachment 1 name';
    is $p->{attachments}->[0]->{src}, 'a1data', 'attachment 1 data';
};

subtest 'tag stack', sub {
    plan tests => 7;
    throws_ok { parse({
        'test.xml' => wrap_xml(q~<ProblemStatement/>~),
    }) } qr/ProblemStatement.+Problem/, 'ProblemStatement outside Problem';
    throws_ok { parse({
        'test.xml' => wrap_xml(q~<Checker/>~),
    }) } qr/Checker.+Problem/, 'Checker outside Problem';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Problem/>~),
    }) } qr/Problem.+CATS/, 'Problem inside Problem';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<In/>~),
    }) } qr/In.+Test/, 'In outside Test';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Out/>~),
    }) } qr/Out.+Test/, 'Out outside Test';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<SampleIn/>~),
    }) } qr/SampleIn.+Sample/, 'SampleIn outside Sample';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<SampleOut/>~),
    }) } qr/SampleOut.+Sample/, 'SampleOut outside SampleTest';
};

subtest 'apply_test_rank', sub {
    plan tests => 5;
    is CATS::Problem::Parser::apply_test_rank('abc', 9), 'abc', 'No rank';
    is CATS::Problem::Parser::apply_test_rank('a%nc', 9), 'a9c', '1 digit';
    is CATS::Problem::Parser::apply_test_rank('a%0nc', 9), 'a09c', '2 digits';
    is CATS::Problem::Parser::apply_test_rank('a%00nc', 9), 'a009c', '3 digits';
    is CATS::Problem::Parser::apply_test_rank('a%%%nc', 9), 'a%9c', 'Escape';
};

subtest 'sample', sub {
    plan tests => 37;

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample/>~),
    }) } qr/Sample.rank/, 'Sample without rank';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample rank="2"><SampleIn>q</SampleIn><SampleOut>w</SampleOut></Sample>~),
    }) } qr/Missing.*1/, 'missing sample';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample rank="1"/>~),
    }) } qr/Neither.*SampleIn.*1/, 'missing SampleIn';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample rank="1"><SampleIn>w</SampleIn></Sample>~),
    }) } qr/Neither.*SampleOut.*1/, 'missing SampleOut';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample rank="1"><SampleIn src="t01.in"/></Sample>~),
    }) } qr/'t01.in'/, 'Sample with nonexisting input file';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample rank="1"><SampleIn src="t01.in"/><SampleOut src="t01.out"/></Sample>~),
        't01.in' => 'z',
    }) } qr/'t01.out'/, 'Sample with nonexisting output file';
    throws_ok { parse({
            'test.xml' => wrap_problem(q~
<Sample rank="1"><SampleIn src="s"><tt>zz</tt></SampleIn><SampleOut>ww</SampleOut></Sample>~),
        's' => 'a',
    }) } qr/Redefined source.*SampleIn.*1/, 'Sample with duplicate input';
    throws_ok { parse({
            'test.xml' => wrap_problem(q~
<Sample rank="1"><SampleIn><tt>zz</tt></SampleIn><SampleOut src="s">ww</SampleOut></Sample>~),
        's' => 'a',
    }) } qr/Redefined source.*SampleOut.*1/, 'Sample with duplicate output';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample rank="1"><SampleIn src="t01.in"/><SampleIn src="t01.in"/></Sample>~),
        't01.in' => 'z',
    }) } qr/Redefined source.*SampleIn.*1/, 'Sample with duplicate input file';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample rank="1"><SampleOut src="t01.in"/><SampleOut src="t01.in"/></Sample>~),
        't01.in' => 'z',
    }) } qr/Redefined source.*SampleOut.*1/, 'Sample with duplicate output file';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample rank="1"><SampleIn>ii</SampleIn><SampleIn>jj</SampleIn></Sample>~),
    }) } qr/Redefined source for SampleIn.*1/, 'Sample with duplicate input text';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample rank="1"><SampleIn>ii</SampleIn><SampleIn/></Sample>~),
    }) } qr/Neither.*SampleOut/, 'SampleIn with empty content';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Sample rank="1"><SampleIn>i</SampleIn><SampleOut>a</SampleOut><SampleOut>b</SampleOut></Sample>~),
    }) } qr/Redefined source for SampleOut.*1/, 'Sample with duplicate output text';
    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<Sample rank="1"><SampleIn src="s"/><SampleOut src="s"/></Sample>
<Sample rank="2"><SampleIn>aaa</SampleIn><SampleOut>bbb</SampleOut></Sample>
<Checker src="checker.pp"/>~),
            'checker.pp' => 'zz',
            's' => 'sss',
        });
        is scalar(keys %{$p->{samples}}), 2, 'Sample count';
        my $s1 = $p->{samples}->{1};
        is $s1->{rank}, 1, 'Sample 1 rank';
        is $s1->{in_file}, 'sss', 'Sample 1 In src';
        is $s1->{out_file}, 'sss', 'Sample 1 Out src';
        my $s2 = $p->{samples}->{2};
        is $s2->{rank}, 2, 'Sample 2 rank';
        is $s2->{in_file}, 'aaa', 'Sample 2 In';
        is $s2->{out_file}, 'bbb', 'Sample 2 Out';
    }
    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<Sample rank="1-2"><SampleIn src="s%n"/></Sample>
<Sample rank="2-3"><SampleOut src="out"/></Sample>
<Sample rank="3"><SampleIn>s33</SampleIn></Sample>
<Sample rank="1"><SampleOut>out</SampleOut></Sample>

<Checker src="checker.pp"/>~),
            'checker.pp' => 'zz',
            's1' => 's11',
            's2' => 's22',
            's3' => 's33',
            'out' => 'out',
        });
        is scalar(keys %{$p->{samples}}), 3, 'Sample range count';
        for (1..3) {
            my $s = $p->{samples}->{$_};
            is $s->{rank}, $_, "Sample range $_ rank";
            is $s->{in_file}, "s$_$_", "Sample range $_ In src";
            is $s->{out_file}, 'out', "Sample range $_ Out src";
        }
    }
    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<Sample rank="1-2"><SampleIn><b>cc</b></SampleIn><SampleOut src="s%0n"/></Sample>
<Checker src="checker.pp"/>~),
            'checker.pp' => 'zz',
            's01' => 's11',
            's02' => 's22',
        });
        is scalar(keys %{$p->{samples}}), 2, 'Sample range count';
        for (1..2) {
            my $s = $p->{samples}->{$_};
            is $s->{rank}, $_, "Sample range $_ rank";
            is $s->{in_file}, '<b>cc</b>', "Sample range $_ In";
            is $s->{out_file}, "s$_$_", "Sample range $_ Out src";
        }
    }
};

subtest 'test', sub {
    plan tests => 62;

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test/>~),
    }) } qr/Test.rank/, 'Test without rank';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="999999"/>~),
    }) } qr/Bad rank/, 'Test with bad rank';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="2"/>~),
    }) } qr/Missing test #1/, 'Missing test 1';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"/>~),
    }) } qr/No input source for test 1/, 'Test without In';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In/></Test>~),
    }) } qr/No input source for test 1/, 'Test with empty In';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In src="t01.in"/></Test>~),
    }) } qr/'t01.in'/, 'Test with nonexinsting input file';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In src="t01.in"/><In src="t01.in"/></Test>~),
        't01.in' => 'z',
    }) } qr/Redefined attribute 'in_file'/, 'Test with duplicate In';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In src="t01.in"/><In>zzz</In></Test>~),
        't01.in' => 'z',
    }) } qr/Redefined attribute 'in_file'/, 'Test with duplicate In text';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In src="t01.in"/></Test>~),
        't01.in' => 'z',
    }) } qr/No output source for test 1/, 'Test without Out';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In src="t01.in"/><Out/></Test>~),
        't01.in' => 'z',
    }) } qr/No output source for test 1/, 'Test with empty Out';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In src="t01.in"/><Out src="t02.out"/></Test>~),
        't01.in' => 'z',
    }) } qr/'t02.out'/, 'Test with nonexinsting output file 1';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1-2"><In src="t01.in"/><Out src="t%0n.out"/></Test>~),
        't01.in' => 'z',
    }) } qr/'t01.out', 't02.out'/, 'Test with nonexinsting output file 2';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In src="t01.in"/><Out src="t01.out"/><Out src="t01.out"/></Test>~),
        't01.in' => 'z',
        't01.out' => 'q',
    }) } qr/Redefined attribute 'out_file'/, 'Test with duplicate Out';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In>zz</In><Out src="t01.out"/><Out>out</Out></Test>~),
        't01.out' => 'q',
    }) } qr/Redefined attribute 'out_file'/, 'Test with duplicate Out text';
    throws_ok { parse({
        'test.xml' => wrap_problem(
            q~<Generator name="g" src="g.pp"/><Test rank="1"><In use="g">z</In><Out>out</Out></Test>~),
        'g.pp' => 'q',
    }) } qr/Both input file and generator/, 'Test with input file and generator';
    throws_ok { parse({
        'test.xml' => wrap_problem(
            q~<Solution name="s" src="s.pp"/><Test rank="1"><In>z</In><Out use="s">out</Out></Test>~),
        's.pp' => 'q',
    }) } qr/Both output file and standard solution/, 'Test with output file and solution';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="2"></Test><Test rank="1"></Test>~),
    }) } qr/No input source for test 1/, 'Test errors in rank order';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1" points="A"><In src="t01.in"/><Out src="t01.out"/></Test>~),
        't01.in' => 'z',
        't01.out' => 'q',
    }) } qr/Bad points/, 'Bad points';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In hash="zzz">1</In><Out>2</Out></Test>~),
    }) } qr/Invalid hash.*zzz.*1/, 'Bad hash';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In hash="$yyy$zz">1</In><Out>2</Out></Test>~),
    }) } qr/Unknown hash algorithm.*yyy.*1/, 'Bad hash algorithm';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In hash="$sha$zz">1</In><In hash="$sha$qq"/><Out>2</Out></Test>~),
    }) } qr/Redefined attribute 'hash'/, 'Redefined hash';

    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<Test rank="1"><In src="t01.in"/><Out src="t01.out"/></Test>
<Checker src="checker.pp"/>~),
            't01.in' => 'z',
            't01.out' => 'q',
            'checker.pp' => 'z',
        });
        is scalar(keys %{$p->{tests}}), 1, 'Test 1';
        my $t = $p->{tests}->{1};
        is $t->{rank}, 1, 'Test 1 rank';
        is $t->{in_file}, 'z', 'Test 1 In src';
        is $t->{out_file}, 'q', 'Test 1 Out src';
    }

    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<Test rank="1"><In/><In>in1</In><Out/></Test>
<Test rank="1"><Out>out1</Out></Test>
<Test rank="2"><In>in2</In><Out>out2</Out></Test>
<Checker src="checker.pp"/>~),
            'checker.pp' => 'z',
        });
        is scalar(keys %{$p->{tests}}), 2, 'Test text';
        for (1..2) {
            my $t = $p->{tests}->{$_};
            is $t->{rank}, $_, 'Test text rank';
            is $t->{in_file}, "in$_", 'Test text In';
            is $t->{out_file}, "out$_", 'Test text Out';
        }
    }

    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<Test rank="1-2" points="5"><In src="t%n.in"/><Out src="t%n.out"/></Test>
<Checker src="checker.pp"/>~),
            't1.in' => 't1in', 't1.out' => 't1out',
            't2.in' => 't2in', 't2.out' => 't2out',
            'checker.pp' => 'z',
        });
        is scalar(keys %{$p->{tests}}), 2, 'Apply %n';
        for (1..2) {
            my $t = $p->{tests}->{$_};
            is $t->{rank}, $_, "Apply $_ rank";
            is $t->{points}, 5, "Apply $_ points";
            is $t->{in_file}, "t${_}in", "Apply $_ In src";
            is $t->{out_file}, "t${_}out", "Apply $_ Out src";
        }
    }

    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<Generator name="gen" src="gen.pp"/>
<Solution name="sol" src="sol.pp"/>
<Test rank="1-5"><In use="gen" param="!%n"/><Out use="sol"/></Test>
<Checker src="chk.pp"/>~),
            'gen.pp' => 'z',
            'sol.pp' => 'z',
            'chk.pp' => 'z',
        });
        is scalar(keys %{$p->{tests}}), 5, 'Gen %n';
        for (1, 2, 5) {
            my $t = $p->{tests}->{$_};
            is $t->{rank}, $_, "Gen $_ rank";
            is $t->{param}, "!$_", "Gen $_ param";
            is $t->{generator_id}, 'gen.pp', "Gen $_ In";
            is $t->{std_solution_id}, 'sol.pp', "Gen $_ Out";
        }
    }

    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<Solution name="sol" src="sol.pp"/>
<Solution name="sol1" src="sol1.pp"/>
<Test rank="*"><In>def</In><Out use="sol"/></Test>
<Test rank="1"><In src="01.in"/></Test>
<Test rank="2"><Out use="sol1"/></Test>
<Checker src="chk.pp"/>~),
            'sol.pp' => 'z',
            'sol1.pp' => 'z',
            '01.in' => 'zz',
            'chk.pp' => 'z',
        });
        is scalar(keys %{$p->{tests}}), 2, 'Default test_count';
        {
            my $t = $p->{tests}->{1};
            is $t->{in_file}, 'zz', 'Default 1 in';
            is $t->{std_solution_id}, 'sol.pp', 'Default 1 out';
        }
        {
            my $t = $p->{tests}->{2};
            is $t->{in_file}, 'def', 'Default 2 in';
            is $t->{std_solution_id}, 'sol1.pp', 'Default 2 out';
        }
    }

    {
        my $parser = ParserMockup::make({
            'test.xml' => wrap_problem(q~
<Test rank="1" points="1"><In src="in"/><Out src="out"/></Test>
<Test rank="2"><In src="in"/><Out src="out"/></Test>
<Checker src="checker.pp" style="testlib"/>~),
            'in' => 'in', 'out' => 'out',
            'checker.pp' => 'z',
        });
        my $p = $parser->parse;
        my $w = $parser->logger->{warnings};
        is scalar @$w, 1, 'point/no-point warnings count';
        is $w->[0], 'Points are defined for tests: 1 but not 2', 'point/no-point warning';
        is scalar(keys %{$p->{tests}}), 2, 'point/no-point tests count';
    }

};

subtest 'testest', sub {
    plan tests => 20;

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Testset/>~),
    }) } qr/Testset.name/, 'Testset without name';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Testset name="ts"/>~),
    }) } qr/Testset.tests/, 'Testset without tests';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Testset name="ts" tests="X"/>~),
    }) } qr/Unknown testset 'X'/, 'Testset with bad tests 1';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Testset name="ts" tests="1-"/>~),
    }) } qr/Bad element/, 'Testset with bad tests 2';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Testset name="ts" tests="1"/>
<Testset name="ts" tests="2"/>~),
    }) } qr/Duplicate testset 'ts'/, 'Duplicate testset';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Testset name="ts" tests="1" points="X"/>~),
    }) } qr/Bad points for testset 'ts'/, 'Bad points';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Testset name="ts" tests="1"/>~),
    }) } qr/Undefined test 1 in testset 'ts'/, 'Undefined test';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Test rank="1-10"><In src="t"/><Out src="t"/></Test>
<Testset name="ts1" tests="1" depends_on="ts2"/>
<Testset name="ts2" tests="2" depends_on="ts1"/>
<Checker src="checker.pp"/>~),
            't' => 'q',
            'checker.pp' => 'z',
    }) } qr/Testset 'ts1' both contains and depends on test 1/, 'Recursive dependency via testest';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Test rank="1-10"><In src="t"/><Out src="t"/></Test>
<Testset name="ts1" tests="1" depends_on="ts2"/>
<Testset name="ts2" tests="2" depends_on="1"/>
<Checker src="checker.pp"/>~),
            't' => 'q',
            'checker.pp' => 'z',
    }) } qr/Testset 'ts1' both contains and depends on test 1/, 'Recursive dependency via test';

    {
        my $p = parse({
            'test.xml' => wrap_problem(q~
<Test rank="1-10"><In src="t"/><Out src="t"/></Test>
<Testset name="ts1" tests="2-5,1" comment="blabla"/>
<Testset name="ts2" tests="ts1,7" hideDetails="1"/>
<Testset name="ts3" tests="10" depends_on="ts1,6"/>
<Checker src="checker.pp"/>~),
            't' => 'q',
            'checker.pp' => 'z',
        });
        is scalar(keys %{$p->{testsets}}), 3, 'Testset count';

        my $ts1 = $p->{testsets}->{ts1};
        is $ts1->{name}, 'ts1', 'Testset 1 name';
        is $ts1->{tests}, '2-5,1', 'Testset 1 tests';
        is $ts1->{comment}, 'blabla', 'Testset 1 comment';
        is $ts1->{hideDetails}, 0, 'Testset 1 hideDetails';

        my $ts2 = $p->{testsets}->{ts2};
        is $ts2->{name}, 'ts2', 'Testset 2 name';
        is $ts2->{tests}, 'ts1,7', 'Testset 2 tests';
        is $ts2->{hideDetails}, 1, 'Testset 2 hideDetails';

        my $ts3 = $p->{testsets}->{ts3};
        is $ts3->{name}, 'ts3', 'Testset 3 name';
        is $ts3->{tests}, '10', 'Testset 2 tests';
        is $ts3->{depends_on}, 'ts1,6', 'Testset 3 depends_on';
    }
};

subtest 'validator', sub {
    plan tests => 10;
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Validator/>~),
    }) } qr/Validator.src/, 'Validator without source';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Validator src="t"/>~),
    }) } qr/Validator.name/, 'Validator without name';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Checker src="t.pp"/>
<Test rank="1"><In src="t" validateParam="1"/><Out src="t"/></Test>~),
        't.pp' => 'q',
        't' => 'w',
    }) } qr/validateParam.+1/, 'validateParam without validate';
    my $p = parse({
        'test.xml' => wrap_problem(q~
<Validator name="val" src="t.pp" inputFile="*STDIN"/>
<Checker src="t.pp"/>
<Test rank="1"><In src="t" validate="val" validateParam="99"/><Out src="t"/></Test>~),
        't.pp' => 'q',
        't' => 'w',
    });
    is @{$p->{validators}}, 1, 'validator count';
    my $v = $p->{validators}->[0];
    is $v->{name}, 'val', 'validator name';
    is $v->{src}, 'q', 'validator source';
    is $v->{inputFile}, '*STDIN', 'validator inputFile';
    is keys(%{$p->{tests}}), 1, 'validator test count';
    is $p->{tests}->{1}->{input_validator_id}, 't.pp', 'validator test validate';
    is $p->{tests}->{1}->{input_validator_param}, '99', 'validator test validate param';
};

subtest 'interactor', sub {
    plan tests => 6;
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Interactor/>~),
    }) } qr/Interactor.src/, 'Interactor without source';

    my $p = parse({
        'test.xml' => wrap_problem(q~
<Interactor name="val" src="t.pp"/>
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q',
    });
    is $p->{interactor}->{src}, 'q', 'interactor source';

    my $parser = ParserMockup::make({
        'test.xml' => wrap_problem(q~<Interactor src="t.pp"/><Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q'
    });
    $parser->parse;
    is $parser->logger->{warnings}->[0],
        'Interactor defined when run method is not interactive or competitive', 'interactor defined when not interactive or competitive';

    $parser = ParserMockup::make({
        'test.xml' => wrap_problem(q~<Run method="interactive" /><Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q'
    });
    $parser->parse;

    is $parser->logger->{warnings}->[0],
        'Interactor is not defined when run method is interactive or competitive (maybe used legacy interactor definition)',
        'interactor not defined';
    $parser = ParserMockup::make({
        'test.xml' => wrap_problem(q~
<Run method="interactive"/>
<Interactor src="t.pp"/>
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q'});
    $parser->parse;
    is @{$parser->logger->{warnings}}, 0, 'interactor normal tag definiton';

    $parser = ParserMockup::make({
        'test.xml' => wrap_problem(q~
<Interactor src="t.pp"/>
<Run method="interactive"/>
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q'
    });
    $parser->parse;
    is @{$parser->logger->{warnings}}, 0, 'interactor inverse tag definition';
};

subtest 'run method', sub {
    plan tests => 10;

    my $p = parse({
        'test.xml' => wrap_problem(q~
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q',
    });
    is $p->{run_method}, $cats::rm_default, 'default run method';

    $p = parse({
        'test.xml' => wrap_problem(q~
<Run method="default" />
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q',
    });
    is $p->{run_method}, $cats::rm_default, 'run method = default';

    $p = parse({
        'test.xml' => wrap_problem(q~
<Run method="interactive" />
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q',
    });
    is $p->{run_method}, $cats::rm_interactive, 'run method = interactive';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Run method="asd" />
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q',
    }) } qr/Unknown run method: /, 'bad run method';

    throws_ok { parse({
        'test.xml' => wrap_problem(q~
<Run method="competitive" />
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q',
    }) } qr/Player count limit must be defined for competitive run method/, 'competetive without player count';

    my $parser = ParserMockup::make({
        'test.xml' => wrap_problem(q~
<Run method="default" players_count="1"/>
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q',
    });
    $p = $parser->parse;
    my $w = $parser->logger->{warnings};
    is scalar @$w, 1, 'players_count when not competitive warnings count';
    is $w->[0], 'Player count limit defined when run method is not competitive',
        'players_count when not competitive warning';

    $p = parse({
        'test.xml' => wrap_problem(q~
<Run method="competitive" players_count="2,3-5"/>
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q',
    });
    is $p->{run_method}, $cats::rm_competitive, 'run method = competitive';
    is $p->{players_count}->[0], 2, 'run method = competitive, players_count = 2';

    $p = parse({
        'test.xml' => wrap_problem(q~
<Run method="competitive" players_count="2,4-5"/>
<Checker src="t.pp" style="testlib"/>~),
        't.pp' => 'q',
    });

    is_deeply $p->{players_count}, [ 2, 4, 5 ], 'run method = competitive, players_count = 2,4-5';
};

subtest 'memory unit suffix', sub {
    plan tests => 12;

    my $parse = sub {
        parse({
        'test.xml' => wrap_xml(qq~
<Problem title="asd" lang="en" tlimit="5" inputFile="asd" outputFile="asd" $_[0]>
<Checker src="checker.pp"/>
</Problem>~),
        'checker.pp' => 'begin end.',
        })->{description}
    };

    throws_ok { $parse->(q/mlimit="asd"/) } qr/Bad value of 'mlimit'/, 'bad mlimit asd';
    throws_ok { $parse->(q/mlimit="K"/) } qr/Bad value of 'mlimit'/, 'bad mlimit K';
    throws_ok { $parse->(q/mlimit="10K"/) } qr/Value of 'mlimit' must be in whole Mbytes/, 'mlimit 10K';
    is $parse->(q/mlimit="1024K"/)->{memory_limit}, 1, 'mlimit 1024K';
    is $parse->(q/mlimit="1M"/)->{memory_limit}, 1, 'mlimit 1M';
    is $parse->(q/mlimit="1"/)->{memory_limit}, 1, 'mlimit 1';

    throws_ok { $parse->(q/wlimit="asd"/) } qr/Bad value of 'wlimit'/, 'bad wlimit asd';
    throws_ok { $parse->(q/wlimit="K"/) } qr/Bad value of 'wlimit'/, 'bad wlimit K';
    is $parse->(q/wlimit="10B"/)->{write_limit}, 10, 'wlimit 10B';
    is $parse->(q/wlimit="2K"/)->{write_limit}, 2048, 'wlimit 2K';
    is $parse->(q/wlimit="1M"/)->{write_limit}, 1048576, 'wlimit 1M';
    is $parse->(q/wlimit="1"/)->{write_limit}, 1048576, 'wlimit 1';
};

subtest 'sources limit params', sub {
    plan tests => 70;

    my $test = sub {
        my ($tag, $getter) = @_;

        my $xml = $tag eq 'Checker' ? q~
        <Checker src="t.pp" style="testlib" %s/>"~ : qq~
        <$tag name="val" src="t.pp" \%s/><Checker src="t.pp" style="testlib"/>~;

        my $parse = sub {
            parse({
                'test.xml' => wrap_problem(sprintf $xml, $_[0]),
                'checker.pp' => 'begin end.', 't.pp' => 'q'
            })
        };

        throws_ok { $parse->(q/memoryLimit="asd"/) } qr/Bad value of 'memoryLimit'/, "bad memoryLimit asd: $tag";
        throws_ok { $parse->(q/memoryLimit="K"/) } qr/Bad value of 'memoryLimit'/, "bad memoryLimit K: $tag";
        throws_ok { $parse->(q/memoryLimit="10K"/) } qr/Value of 'memoryLimit' must be in whole Mbytes/, "memoryLimit 10K: $tag";
        is $getter->($parse->(q/memoryLimit="1024K"/))->{memory_limit}, 1, "memoryLimit 1024K: $tag";
        is $getter->($parse->(q/memoryLimit="1M"/))->{memory_limit}, 1, "memoryLimit 1M: $tag";
        is $getter->($parse->(q/memoryLimit="1"/))->{memory_limit}, 1, "memoryLimit 1: $tag";
        is $getter->($parse->(q/memoryLimit="1G"/))->{memory_limit}, 1024, "memoryLimit 1G: $tag";

        throws_ok { $parse->(q/writeLimit="asd"/) } qr/Bad value of 'writeLimit'/, "bad writeLimit asd: $tag";
        throws_ok { $parse->(q/writeLimit="K"/) } qr/Bad value of 'writeLimit'/, "bad writeLimit K: $tag";
        is $getter->($parse->(q/writeLimit="10B"/))->{write_limit}, 10, "writeLimit 10B: $tag";
        is $getter->($parse->(q/writeLimit="2K"/))->{write_limit}, 2048, "writeLimit 2K: $tag";
        is $getter->($parse->(q/writeLimit="1M"/))->{write_limit}, 1048576, "writeLimit 1M: $tag";
        is $getter->($parse->(q/writeLimit="1"/))->{write_limit}, 1048576, "writeLimit 1: $tag";
        is $getter->($parse->(q/writeLimit="1G"/))->{write_limit}, 1024 * 1048576, "writeLimit 1G: $tag";
    };

    $test->('Generator', sub { $_[0]->{generators}[0] });
    $test->('Solution', sub { $_[0]->{solutions}[0] });
    $test->('Visualizer', sub { $_[0]->{visualizers}[0] });
    $test->('Checker', sub { $_[0]->{checker} });
    $test->('Interactor', sub { $_[0]->{interactor} });
};

subtest 'linter', sub {
    plan tests => 3;

    my $parse = sub {
        my ($stage) = @_;
        parse({
        'test.xml' => wrap_xml(qq~
<Problem title="asd" lang="en" tlimit="5" inputFile="asd" outputFile="asd" $_[0]>
<Checker src="checker.pp"/>
<Linter name="lint" src="checker.pp" $stage/>
</Problem>~),
        'checker.pp' => 'begin end.',
        });
    };

    throws_ok { $parse->('') } qr/Linter\.stage/, 'no stage';
    throws_ok { $parse->('stage="qqq"') } qr/'qqq'/, 'bad stage';
    is $parse->(q/stage="before"/)->{linters}->[0]->{stage}, 'before', 'before';
};
