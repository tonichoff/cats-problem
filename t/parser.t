package Logger;

#use Carp;
sub new { bless {}, $_[0]; }
sub note {}
sub warning {}
sub error { die $_[1] }

package main;

use strict;
use warnings;

use lib '..';

use Test::More tests => 11;
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
        id_gen => sub { $_[1] },
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

subtest 'test', sub {
    plan tests => 36;

    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test/>~),
    }) } qr/Test.rank/, 'Test without rank';
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
    }) } qr/t01/, 'Test with nonexinsting input file';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In src="t01.in"/><In src="t01.in"/></Test>~),
        't01.in' => 'z',
    }) } qr/Redefined attribute 'in_file'/, 'Test with duplicate In';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In src="t01.in"/></Test>~),
        't01.in' => 'z',
    }) } qr/No output source for test 1/, 'Test without Out';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In src="t01.in"/><Out/></Test>~),
        't01.in' => 'z',
    }) } qr/No output source for test 1/, 'Test with empty Out';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1"><In src="t01.in"/><Out src="t01.out"/><Out src="t01.out"/></Test>~),
        't01.in' => 'z',
        't01.out' => 'q',
    }) } qr/Redefined attribute 'out_file'/, 'Test with duplicate Out';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Test rank="1" points="A"><In src="t01.in"/><Out src="t01.out"/></Test>~),
        't01.in' => 'z',
        't01.out' => 'q',
    }) } qr/Bad points/, 'Bad points';

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
    }) } qr/Recursive/, 'Recursive dependency via testest';

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
    plan tests => 8;
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Validator/>~),
    }) } qr/Validator.src/, 'Validator without source';
    throws_ok { parse({
        'test.xml' => wrap_problem(q~<Validator src="t"/>~),
    }) } qr/Validator.name/, 'Validator without name';
    my $p = parse({
        'test.xml' => wrap_problem(q~
<Validator name="val" src="t.pp" inputFile="*STDIN"/>
<Checker src="t.pp"/>
<Test rank="1"><In src="t" validate="val"/><Out src="t"/></Test>~),
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
};
