package CATS::Problem::PolygonParser;

use strict;
use warnings;

use XML::Parser::Expat;

sub new {
    my ($class, %opts) = @_;
    $opts{source} or die "Unknown source for parser";
    $opts{problem} = CATS::Problem->new;
    $opts{id_gen} or die 'Unknown id generator';
    return bless \%opts => $class;
}

sub error {
    my CATS::Problem::PolygonParser $self = shift;
    $self->{source}->error(@_);
}

sub warning {
    my CATS::Problem::PolygonParser $self = shift;
    $self->{source}->warning(@_);
}

sub tag_handlers() {{
    problem => { s => \&start_tag_problem },
    names => {},
    name => { s => \&start_tag_name },
    statements => {},
    statement => {},
    judging => { s => \&start_tag_judging },
    'judging/testset' => { s => \&start_tag_judging_testset, e => \&end_tag_judging_testset },
    tests => {},
    test => { s => \&start_tag_test },
    'time-limit' => { e => \&end_tag_time_limit },
    'memory-limit' => { e => \&end_tag_memory_limit },
    'test-count' => { e => \&end_tag_test_count },
    'input-path-pattern' => { e => \&end_tag_input_pattern },
    'output-path-pattern' => {},
    'answer-path-pattern' => { e => \&end_tag_answer_pattern },
    'stress-file-pattern' => {},
    files => {},
    resources => {},
    file => { s => \&start_tag_file },
    executables => {},
    executable => {},
    'checker/source' => { s => \&start_tag_checker_source },
    'solution/source' => { s => \&start_tag_solution_source },
    'validator/source' => { s => \&start_tag_validator_source },
    'executable/source' => { s => \&start_tag_executable_source },
    binary => {},
    assets => {},
    checker => {},
    'checker/testset' => {},
    copy => {},
    list => {},
    solutions => {},
    solution => {},
    validators => {},
    validator => {},
    'validator/testset' => {},
    tags => {},
    tag => {},
    properties => {},
    property => {},
    stresses => {},
    'stress-count' => {},
    'stress-path-pattern' => {},
    documents => {},
    document => {},
}}

sub set_named_object {
    my CATS::Problem::PolygonParser $self = shift;
    my ($name, $object) = @_;
    $name or return;
    $self->error("Duplicate object reference: '$name'")
        if defined $self->{objects}->{$name};
    $self->{objects}->{$name} = $object;
}

sub get_named_object {
    (my CATS::Problem::PolygonParser $self, my $name, my $kind) = @_;
    defined $name or return undef;
    defined (my $result = $self->{objects}->{$name})
        or $self->error_stack("Undefined object reference: '$name'");
    defined $kind && $result->{kind} ne $kind
        and $self->error_stack("Object '$name' is '$result->{kind}' instead of '$kind'");
    $result;
}

sub problem_source_common_params {
    (my CATS::Problem::PolygonParser $self, my $atts, my $kind) = @_;
    return (
        id => $self->{id_gen}->($self, $atts->{name}),
        $self->read_member_named(name => $atts->{src}, kind => $kind),
    );
}

sub start_tag_problem {
    (my CATS::Problem::PolygonParser $self, my $atts) = @_;
    $self->{problem}{description}{title} = $atts->{'short-name'} || $atts->{'name'};
}

sub start_tag_name {
    (my CATS::Problem::PolygonParser $self, my $atts) = @_;
    #$self->{problem}{description}{title} = $atts->{value};
}

sub start_tag_judging {
    (my CATS::Problem::PolygonParser $self, my $atts) = @_;
    $self->{problem}{description}{input_file} = $atts->{'input-file'} || '*STDIN';
    $self->{problem}{description}{output_file} = $atts->{'output-file'} || '*STDOUT';
}

sub start_tag_judging_testset {
    (my CATS::Problem::PolygonParser $self, my $atts) = @_;
    $self->{current_testset} = {
        name => $atts->{name},
        tests => [],
        test_now => 0,
        count => undef,
        input_path_pattern => undef,
        answer_path_pattern => undef,
        time_limit => undef,
        memory_limit => undef,
    };
}

sub end_tag_judging_testset {
    (my CATS::Problem::PolygonParser $self, my $atts) = @_;
    my $testset = $self->{current_testset} or die;
    ${$self->{problem}{tests}}{$_->{rank}} = $_ for @{$testset->{tests}};
    $self->{problem}{description}{memory_limit} = $testset->{memory_limit};
    $self->{problem}{description}{time_limit} = $testset->{time_limit};
    delete $self->{current_testset};
}

sub start_tag_test {
    (my CATS::Problem::PolygonParser $self, my $atts) = @_;
    my $testset = $self->{current_testset} or $self->error("bad tag test");
    $testset->{name} or return;
    $testset->{count} < ++$testset->{test_now} and $self->error("bad test in testset $testset->{name}");
    $atts->{method} or $self->error('missing attribute method in test');
    my $rank = $testset->{test_now};
    if ($atts->{method} eq 'manual') {
        my $source_dir = $self->{source}{dir};
        my $path = sprintf($testset->{input_path_pattern}, $testset->{test_now});
        my $in_file = $self->{source}->read_member($path);
        push @{$testset->{tests}}, {
            rank => $rank,
            in_file => $in_file,
            std_solution_id => undef,
        };
    } elsif ($atts->{method} eq 'generated') {
        $atts->{cmd} or $self->error("missing attribute cmd for test where method $atts->{method}");
        my ($generator_id, $param) = $atts->{cmd} =~ m/^([\S]*)\s([^|]*)(\|.*)?$/;
        $self->{can_generator}{$generator_id} = 1;
        push @{$testset->{tests}}, {
            rank => $rank,
            generator_id => $self->{id_gen}->($self, $generator_id),
            param => $param,
        };
    }
    else {
        $self->error('bad tag test');
    }
}

sub end_tag_time_limit {
    (my CATS::Problem::PolygonParser $self, my $atts) = @_;
    # Polygon time-limit in miliseconds
    $self->{current_testset}{time_limit} = $self->{Char} / 1000;
}

sub end_tag_memory_limit {
    (my CATS::Problem::PolygonParser $self, my $atts) = @_;
    # Polygon memory-limit in bytes
    $self->{current_testset}{memory_limit} = $self->{Char} / 1024 / 1024;
}

sub end_tag_test_count {
    (my CATS::Problem::PolygonParser $self, my $atts) = @_;
    my $testset = $self->{current_testset};
    length $self->{Char} or $self->error("bad testset $testset->{name}, missing char of test_count");
    $testset->{count} = $self->{Char};
}

sub end_tag_input_pattern {
    (my CATS::Problem::PolygonParser $self, my $atts) = @_;
    $self->{current_testset}{input_path_pattern} = $self->{Char};
}

sub end_tag_answer_pattern {
    (my CATS::Problem::PolygonParser $self, my $atts) = @_;
    $self->{current_testset}{answer_path_pattern} = $self->{Char};
}

sub start_tag_file {
    (my CATS::Problem::PolygonParser $self, my $atts) = @_;
    $atts->{path} =~ m/testlib.h/ or return;
    $self->{testlib} = $atts->{path};
    $self->{has_testlib} = 1;
}

sub modify_atts {
    my $atts = shift;
    $atts->{src} = $atts->{path};
    ($atts->{name}) = $atts->{path} =~ m/\/(.*)\..*$/;
}

sub start_tag_checker_source {
    (my CATS::Problem::PolygonParser $self, my $atts) = @_;
    $self->checker_added;
    modify_atts(\%$atts);
    $self->{problem}{checker} = {
        $self->problem_source_common_params($atts, 'checker'),
        style => 'testlib'
    };
}

sub start_tag_solution_source {
    (my CATS::Problem::PolygonParser $self, my $atts) = @_;
    modify_atts(\%$atts);
    my $sol = $self->set_named_object($atts->{name}, {
        $self->problem_source_common_params($atts, 'solution'),
    });
    push @{$self->{problem}{solutions}}, $sol;
    ${$self->{tag_stack}}[-2]->{atts}{tag} eq 'main' or return;
    $_->{std_solution_id} = ${$self->{problem}{solutions}}[-1]->{id} for values %{$self->{problem}{tests}};
}

sub start_tag_validator_source {
    (my CATS::Problem::PolygonParser $self, my $atts) = @_;
    modify_atts(\%$atts);
    my $val = $self->set_named_object($atts->{name}, {
        $self->problem_source_common_params($atts, 'validator'),
    });
    push @{$self->{problem}{validators}}, $val;
}

sub start_tag_executable_source {
    (my CATS::Problem::PolygonParser $self, my $atts) = @_;
    modify_atts(\%$atts);
    $self->{can_generator}{$atts->{name}} or return;
    my $generator = $self->set_named_object($atts->{name}, {
        $self->problem_source_common_params($atts, 'generator'),
        outputFile => '*STDOUT',
    });
    $generator->{name} = $atts->{name};
    push @{$self->{problem}{generators}}, $generator;
}

sub on_start_tag {
    my CATS::Problem::PolygonParser $self = shift;
    my ($p, $el, %atts) = @_;
    my $stack = $self->{tag_stack};
    my $h =
        tag_handlers()->{$el} ? tag_handlers()->{$el} :
        @$stack > 1 ? tag_handlers()->{ "$stack->[-1]->{name}/$el" } : undef
        or $self->error("Unknown tag '$el'");
    push @$stack, { name => $el, atts => \%atts };
    $h->{s}->($self, \%atts, $el) if $h->{s};
}

sub on_end_tag {
    my CATS::Problem::PolygonParser $self = shift;
    my ($p, $el, %atts) = @_;
    my $h = tag_handlers()->{$el} ? tag_handlers()->{$el} :
        tag_handlers()->{ "${$self->{tag_stack}}[-2]->{name}/$el" }
        or $self->error("Unknown tag $el");
    $h->{e} and $h->{e}->($self, \%atts, $el);
    pop @{$self->{tag_stack}};
}

sub read_member_named {
    (my CATS::Problem::PolygonParser $self, my %p) = @_;
    return (
        src => $self->{source}->read_member($p{name}, "Invalid $p{kind} reference: '$p{name}'"),
        path => $p{name},
        kind => $p{kind},
    );
}

sub checker_added {
    my CATS::Problem::PolygonParser $self = shift;
    $self->{problem}{has_checker} and $self->error('Found several checkers');
    $self->{problem}{has_checker} = 1;
}

sub parse_xml {
    (my CATS::Problem::PolygonParser $self, my $xml_file) = @_;
    $self->{tag_stack} = [];
    my $xml_parser = XML::Parser::Expat->new;
    $xml_parser->setHandlers(
        Start => sub { $self->on_start_tag(@_) },
        End => sub { $self->on_end_tag(@_) },
        Char => sub { $self->{Char} = $_[1]; },
    );
    $xml_parser->parse($self->{source}->read_member($xml_file));

    if ($self->{has_testlib}) {
        for (qw[checker validator generator]) {
            push @{$self->{problem}{modules}}, {
                id => $self->{id_gen}->($self, 'testlib.h'),
                $self->read_member_named(name => $self->{testlib}, kind => 'module'),
                de_code => 1,
                type => $_,
                type_code => CATS::Problem::module_types()->{$_},
            }
        }
    }

    $self->{problem}->{run_method} = $cats::rm_default;
}

sub parse {
    my $self = shift;
    $self->{source}->init;
    $self->{problem} = {};
    my @xml_members = $self->{source}->find_members('\.xml$');
    @xml_members or $self->error('*.xml not found');
    @xml_members > 1 and $self->error('found several *.xml in archive');
    $self->parse_xml($xml_members[0]);
    return $self->{problem};
}

1;
