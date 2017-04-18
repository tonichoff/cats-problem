package CATS::Problem::Parser;

use strict;
use warnings;

use Encode;
use JSON::XS;
use XML::Parser::Expat;

use CATS::Constants;
use CATS::Problem;
use CATS::Utils qw(escape_xml);

my $has_formal_input;
BEGIN { $has_formal_input = eval { require FormalInput; 1; } }

use CATS::Problem::TestsParser;

sub new
{
    my ($class, %opts) = @_;
    $opts{source} or die "Unknown source for parser";
    $opts{problem} = CATS::Problem->new(%{$opts{problem_desc}});
    $opts{import_source} or die 'Unknown import source';
    $opts{id_gen} or die 'Unknown id generator';
    delete $opts{problem_desc};
    return bless \%opts => $class;
}

sub logger { $_[0]->{source}->{logger} }

sub error
{
    my CATS::Problem::Parser $self = shift;
    $self->{source}->error(@_);
}

sub error_stack
{
    (my CATS::Problem::Parser $self, my $msg) = @_;
    $self->error("$msg in " . join '/', @{$self->{tag_stack}});
}

sub note
{
    my CATS::Problem::Parser $self = shift;
    $self->{source}->note(@_);
}

sub warning
{
    my CATS::Problem::Parser $self = shift;
    $self->{source}->warning(@_);
}

sub get_zip
{
    $_[0]->{source}->get_zip;
}

sub tag_handlers()
{{
    CATS => { s => sub {}, r => ['version'], in => [] },
    ProblemStatement => { stml_src_handlers('statement') },
    ProblemConstraints => { stml_handlers('constraints') },
    InputFormat => { stml_handlers('input_format') },
    OutputFormat => { stml_handlers('output_format') },
    FormalInput => { s => start_stml('formal_input'), e => \&end_tag_FormalInput },
    JsonData => { s => start_stml('json_data'), e => \&end_tag_JsonData },
    Explanation => { stml_src_handlers('explanation') },
    Problem => {
        s => \&start_tag_Problem, e => \&end_tag_Problem,
        r => ['title', 'lang', 'tlimit', 'inputFile', 'outputFile'], in => ['CATS']},
    Attachment => { s => \&start_tag_Attachment, r => ['src', 'name'] },
    Picture => { s => \&start_tag_Picture, r => ['src', 'name'] },
    Solution => { s => \&start_tag_Solution, r => ['src', 'name'] },
    Checker => { s => \&start_tag_Checker, r => ['src'] },
    Interactor => { s => \&start_tag_Interactor, r => ['src'] },
    Generator => { s => \&start_tag_Generator, r => ['src', 'name'] },
    Validator => { s => \&start_tag_Validator, r => ['src', 'name'] },
    Visualizer => { s => \&start_tag_Visualizer, r => ['src', 'name'] },
    GeneratorRange => {
        s => \&start_tag_GeneratorRange, r => ['src', 'name', 'from', 'to'] },
    Module => { s => \&start_tag_Module, r => ['src', 'de_code', 'type'] },
    Import => { s => \&start_tag_Import, r => ['guid'] },
    Test => { s => \&start_tag_Test, e => \&end_tag_Test, r => ['rank'] },
    TestRange => {
        s => \&start_tag_TestRange, e => \&end_tag_Test, r => ['from', 'to'] },
    In => { s => \&start_tag_In, in => ['Test', 'TestRange'] },
    Out => { s => \&start_tag_Out, in => ['Test', 'TestRange'] },
    Sample => { s => \&start_tag_Sample, e => \&end_tag_Sample, r => ['rank'] },
    SampleIn => { s => \&start_tag_SampleIn, e => \&end_stml, in => ['Sample'] },
    SampleOut => { s => \&start_tag_SampleOut, e => \&end_stml, in => ['Sample'] },
    Keyword => { s => \&start_tag_Keyword, r => ['code'] },
    Testset => { s => \&start_tag_Testset, r => ['name', 'tests'] },
    Run => { s => \&start_tag_Run, r => ['method'] },
}}

sub required_attributes
{
    my CATS::Problem::Parser $self = shift;
    my ($el, $attrs, $names) = @_;
    for (@$names) {
        defined $attrs->{$_}
            or $self->error("$el.$_ not specified");
    }
}

sub set_named_object
{
    my CATS::Problem::Parser $self = shift;
    my ($name, $object) = @_;
    $name or return;
    $self->error("Duplicate object reference: '$name'")
        if defined $self->{objects}->{$name};
    $self->{objects}->{$name} = $object;
}

sub get_named_object
{
    (my CATS::Problem::Parser $self, my $name, my $kind) = @_;

    defined $name or return undef;
    defined(my $result = $self->{objects}->{$name})
        or $self->error_stack("Undefined object reference: '$name'");
    defined $kind && $result->{kind} ne $kind
        and $self->error_stack("Object '$name' is '$result->{kind}' instead of '$kind'");
    $result;
}

sub get_imported_id
{
    (my CATS::Problem::Parser $self, my $name) = @_;

    for (@{$self->{problem}{imports}}) {
        return $_->{src_id} if $name eq ($_->{name} || '');
    }
    undef;
}

sub read_member_named
{
    (my CATS::Problem::Parser $self, my %p) = @_;

    return (
        src => $self->{source}->read_member($p{name}, "Invalid $p{kind} reference: '$p{name}'"),
        path => $p{name},
        kind => $p{kind},
    );
}

sub check_top_tag
{
    (my CATS::Problem::Parser $self, my $allowed_tags) = @_;
    my $top_tag;
    $top_tag = @$_ ? $_->[$#$_] : '' for $self->{tag_stack};
    return grep $top_tag eq $_, @$allowed_tags;
}

sub checker_added
{
    my CATS::Problem::Parser $self = shift;
    $self->{problem}{has_checker} and $self->error('Found several checkers');
    $self->{problem}{has_checker} = 1;
}

sub create_generator
{
    (my CATS::Problem::Parser $self, my $p) = @_;

    return $self->set_named_object($p->{name}, {
        $self->problem_source_common_params($p, 'generator'),
        outputFile => $p->{outputFile},
    });
}

sub create_validator
{
    (my CATS::Problem::Parser $self, my $p) = @_;

    return $self->set_named_object($p->{name}, {
        $self->problem_source_common_params($p, 'validator'),
        inputFile => $p->{inputFile},
    });
}

sub create_visualizer
{
    (my CATS::Problem::Parser $self, my $p) = @_;

    return $self->set_named_object($p->{name}, {
        $self->problem_source_common_params($p, 'visualizer')
    });
}

sub validate
{
    my CATS::Problem::Parser $self = shift;

    my $check_order = sub {
        my ($objects, $name) = @_;
        for (1 .. keys %$objects) {
            exists $objects->{$_} or $self->error("Missing $name #$_");
        }
    };

    my $problem = $self->{problem};
    $self->apply_test_defaults;
    $check_order->($problem->{tests}, 'test');
    my @t = values %{$problem->{tests}};
    for (sort {$a->{rank} <=> $b->{rank}} @t) {
        my $error = validate_test($_) or next;
        $self->error("$error for test $_->{rank}");
    }
    my @no_points = ([], []);
    push @{$no_points[defined $_->{points} ? 0 : 1]}, $_->{rank} for @t;
    $self->warning(sprintf 'Points are defined for tests: %s but not %s',
        map CATS::Testset::pack_rank_spec(@$_), @no_points) if @{$no_points[0]} && @{$no_points[1]};
    $self->validate_testsets;

    $check_order->($problem->{samples}, 'sample');

    $problem->{run_method} ||= $cats::rm_default;

    $problem->{$_} && $problem->{description}->{"${_}_url"}
        and $self->warning("Both stml and url for $_") for qw(statement explanation);
    $problem->{has_checker} or $self->error('No checker specified');

    $problem->{interactor} and $problem->{run_method} != $cats::rm_interactive
        and $self->warning("Interactor defined when run method is not interactive");

    $problem->{run_method} == $cats::rm_interactive and !$problem->{interactor}
        and $self->warning("Interactor is not defined when run method is interactive (maybe used legacy interactor definition)");
}

sub inc_object_ref_count
{
    (my CATS::Problem::Parser $self, my $name, my $kind) = @_;
    defined $name and $self->get_named_object($name, $kind)->{refcount}++;
}

sub on_start_tag
{
    my CATS::Problem::Parser $self = shift;
    my ($p, $el, %atts) = @_;

    my $h = tag_handlers()->{$el};
    if (my $stml = $self->{stml}) {
        $h and $self->error("Unexpected top-level tag $el inside stml of " . $self->{tag_stack}->[-1]);
        if ($el eq 'include') {
            my $name = $atts{src} or
                return $self->error(q~Missing required 'src' attribute of 'include' tag~);
            $$stml .= Encode::decode(
                $self->{problem}{encoding}, $self->{source}->read_member($name, "Invalid 'include' reference: '$name'"));
            return;
        }
        $$stml .=
            "<$el" . join ('', map qq~ $_="$atts{$_}"~, keys %atts) . '>';

        $el ne 'img' || $atts{picture} or
            $self->error('Picture not defined in img element');

        my $attr = { img => 'picture', a => 'attachment', object => 'attachment' }->{$el};
        $self->inc_object_ref_count($atts{$attr}, $attr) if $attr;
        return;
    }

    $h or $self->error("Unknown tag $el");
    my $in = $h->{in} // ['Problem'];
    !@$in || $self->check_top_tag($in)
        or $self->error_stack("Tag '$el' must be inside of " . join(' or ', @$in));
    $self->required_attributes($el, \%atts, $h->{r}) if $h->{r};
    push @{$self->{tag_stack}}, $el;
    $h->{s}->($self, \%atts, $el);
}

sub on_end_tag
{
    my CATS::Problem::Parser $self = shift;
    my ($p, $el, %atts) = @_;

    my $h = tag_handlers()->{$el};
    $h->{e}->($self, \%atts, $el) if $h && $h->{e};
    if ($self->{stml}) {
        ${$self->{stml}} .= "</$el>" if $el ne 'include';
        return;
    }
    $h or $self->error("Unknown tag $el");
    $el eq pop @{$self->{tag_stack}} or $self->error("Mismatched closing tag $el");
}

sub start_stml {
    my ($v) = @_;
    sub { $_[0]->{stml} = \$_[0]->{problem}->{$v} };
}

sub end_stml { undef $_[0]->{stml} }

sub stml_handlers { return (s => start_stml(@_), e => \&end_stml); }

sub stml_src_handlers
{
    my $start = start_stml(@_);
    my ($field) = @_;
    (
        s => sub {
            (my CATS::Problem::Parser $self, my $atts) = @_;
            $start->(@_);
            my $problem = $self->{problem}->{description};
            for my $src (qw(attachment url)) {
                my $n = $atts->{$src} or next;
                my $url_field = "${field}_url";
                $problem->{$url_field} and $self->error("Several $url_field resources");
                $problem->{$url_field} = $n;
                if ($src eq 'attachment') {
                    $problem->{$url_field} = "file://$n";
                    $self->inc_object_ref_count($n, 'attachment');
                }
                $self->note("$url_field set to $src '$n'");
            }
        },
        e => \&end_stml
    );
}

sub end_tag_FormalInput
{
    (my CATS::Problem::Parser $self, my $atts) = @_;
    $has_formal_input or return $self->warning('Parsing FormalInput tag requires FormalInput module');
    my $parser_err = FormalInput::parserValidate(${$self->{stml}});
    if ($parser_err) {
        my $s = FormalInput::errorMessageByCode(FormalInput::getErrCode($parser_err));
        my $l = FormalInput::getErrLine($parser_err);
        my $p = FormalInput::getErrPos($parser_err);
        $self->error("FormalInput: $s. Line: $l. Pos: $p.");
    } else {
        $self->note('FormalInput OK.');
    }
    $self->end_stml;
}

sub end_tag_JsonData
{
    (my CATS::Problem::Parser $self, my $atts) = @_;
    ${$self->{stml}} = Encode::encode_utf8(${$self->{stml}});
    eval { decode_json(${$self->{stml}}) };
    if ($@) {
        $self->error("JsonData: $@");
    } else {
        $self->note('JsonData OK.');
    }
    $self->end_stml;
}

sub start_tag_Problem
{
    (my CATS::Problem::Parser $self, my $atts) = @_;

    my $problem = $self->{problem};

    my $parse_memory_unit = sub {
        my ($str, $convert_to, $limit_name) = @_;

        $str or return undef;
        $str =~ m/^(\d+)(M|K|B)?$/ or $self->error("Bad $limit_name limit");

        my %m = (
            B => 1,
            K => 1 << 10,
            M => 1 << 20,
        );

        my $bytes = $1 * $m{$2 || 'M'};

        $bytes % $m{$convert_to} ? $self->error("Value of $limit_name must be in whole ${convert_to}bytes") : $bytes / $m{$convert_to};
    };

    $problem->{description} = {
        title => $atts->{title},
        lang => $atts->{lang},
        time_limit => $atts->{tlimit},
        memory_limit => $parse_memory_unit->($atts->{mlimit}, 'M', 'memory'),
        write_limit => $parse_memory_unit->($atts->{wlimit}, 'B', 'write'),
        difficulty => $atts->{difficulty},
        author => $atts->{author},
        input_file => $atts->{inputFile},
        output_file => $atts->{outputFile},
        std_checker => $atts->{stdChecker},
        max_points => $atts->{maxPoints},
    };
    for ($problem->{description}{memory_limit}) {
        last if defined $_;
        $_ = 200;
        $self->warning("Problem.mlimit not specified. default: $_");
    }

    if ($problem->{description}{std_checker}) {
        $self->warning("Deprecated attribute 'stdChecker', use Import instead");
        $self->checker_added;
    }

    my $ot = $problem->{old_title};
    $self->error(sprintf
        "Unexpected problem rename from: $ot to: $problem->{description}{title}",
    ) if $ot && $problem->{description}{title} ne $ot;
}

sub end_tag_Problem
{
    $_[0]->validate;
}

sub start_tag_Attachment
{
    (my CATS::Problem::Parser $self, my $atts) = @_;

    push @{$self->{problem}{attachments}},
        $self->set_named_object($atts->{name}, {
            id => $self->{id_gen}->($self, $atts->{src}),
            $self->read_member_named(name => $atts->{src}, kind => 'attachment'),
            name => $atts->{name}, file_name => $atts->{src}, refcount => 0
        });
}

sub start_tag_Picture
{
    (my CATS::Problem::Parser $self, my $atts) = @_;

    $atts->{src} =~ /\.([^\.]+)$/ and my $ext = $1
        or $self->error("Invalid image extension for '$atts->{src}'");

    push @{$self->{problem}{pictures}},
        $self->set_named_object($atts->{name}, {
            id => $self->{id_gen}->($self, $atts->{src}),
            $self->read_member_named(name => $atts->{src}, kind => 'picture'),
            name => $atts->{name}, ext => $ext, refcount => 0
        });
}

sub problem_source_common_params
{
    (my CATS::Problem::Parser $self, my $atts, my $kind) = @_;
    return (
        id => $self->{id_gen}->($self, $atts->{src}),
        $self->read_member_named(name => $atts->{src}, kind => $kind),
        de_code => $atts->{de_code},
        guid => $atts->{export},
        time_limit => $atts->{timeLimit},
        memory_limit => $atts->{memoryLimit},
        name => $atts->{name},
    );
}

sub start_tag_Solution
{
    (my CATS::Problem::Parser $self, my $atts) = @_;

    my $sol = $self->set_named_object($atts->{name}, {
        $self->problem_source_common_params($atts, 'solution'),
        checkup => $atts->{checkup},
    });
    push @{$self->{problem}{solutions}}, $sol;
}

sub start_tag_Checker
{
    (my CATS::Problem::Parser $self, my $atts) = @_;

    my $style = $atts->{style} || 'legacy';
    CATS::Problem::checker_type_names->{$style}
        or $self->error(q~Unknown checker style (must be 'legacy', 'testlib' or 'partial')~);
    $style ne 'legacy'
        or $self->warning('Legacy checker found!');
    $self->checker_added;
    $self->{problem}{checker} = {
        $self->problem_source_common_params($atts, 'checker'), style => $style
    };
}

sub start_tag_Interactor
{
    (my CATS::Problem::Parser $self, my $atts) = @_;

    $self->error("Found several interactors") if exists $self->{problem}{interactor};

    $self->{problem}{interactor} = {
        $self->problem_source_common_params($atts, 'interactor')
    };
}

sub start_tag_Generator
{
    (my CATS::Problem::Parser $self, my $atts) = @_;
    push @{$self->{problem}{generators}}, $self->create_generator($atts);
}

sub start_tag_Validator
{
    (my CATS::Problem::Parser $self, my $atts) = @_;
    push @{$self->{problem}{validators}}, $self->create_validator($atts);
}

sub start_tag_Visualizer
{
    (my CATS::Problem::Parser $self, my $atts) = @_;
    push @{$self->{problem}{visualizers}}, $self->create_visualizer($atts);
}

sub start_tag_GeneratorRange
{
    (my CATS::Problem::Parser $self, my $atts) = @_;
    for ($atts->{from} .. $atts->{to}) {
        push @{$self->{problem}{generators}}, $self->create_generator({
            name => apply_test_rank($atts->{name}, $_),
            src => apply_test_rank($atts->{src}, $_),
            export => apply_test_rank($atts->{export}, $_),
            de_code => $atts->{de_code},
            outputFile => $atts->{outputFile},
        });
    }
}

sub start_tag_Module
{
    (my CATS::Problem::Parser $self, my $atts) = @_;

    exists CATS::Problem::module_types()->{$atts->{type}}
        or $self->error("Unknown module type: '$atts->{type}'");
    push @{$self->{problem}{modules}}, {
        id => $self->{id_gen}->($self, $atts->{src}),
        $self->read_member_named(name => $atts->{src}, kind => 'module'),
        de_code => $atts->{de_code},
        guid => $atts->{export}, type => $atts->{type},
        type_code => CATS::Problem::module_types()->{$atts->{type}},
    };
}

sub import_one_source
{
    my CATS::Problem::Parser $self = shift;
    my ($guid, $name, $type) = @_;
    push @{$self->{problem}{imports}}, my $import = { guid => $guid, name => $name };
    my ($src_id, $stype) = $self->{import_source}->get_source($guid);

    !$type || ($type = $import->{type} = CATS::Problem::module_types()->{$type})
        or $self->error("Unknown import source type: $type");

    if ($src_id) {
        !$type || $stype == $type || $cats::source_modules{$stype} == $type
            or $self->error(sprintf q~Import type check failed for guid='%s' expected: '%s' got: '%s'~,
                $guid, map $cats::source_module_names{$_}, $type, $stype);
        $self->checker_added
            if defined $cats::source_modules{$stype} && $cats::source_modules{$stype} == $cats::checker_module;
        $import->{src_id} = $src_id;
        $self->note("Imported source from guid='$guid'");
    } else {
        $self->warning("Import source not found for guid='$guid'");
    }

}

sub start_tag_Import
{
    (my CATS::Problem::Parser $self, my $atts) = @_;

    my ($guid, @nt) = @$atts{qw(guid name type)};
    if ($guid =~ /\*/) {
        $self->import_one_source($_, @nt) for $self->{import_source}->get_guids($guid);
    } else {
        $self->import_one_source($guid, @nt);
    }
}

sub start_tag_Sample
{
    (my CATS::Problem::Parser $self, my $atts) = @_;

    $self->{current_samples} =
        CATS::Testset::parse_simple_rank($atts->{rank}, sub { $self->error(@_) });
    my $ps = $self->{problem}->{samples} //= {};
    for (@{$self->{current_samples}}) {
        $self->error("Duplicate sample $_") if defined $ps->{$_};
        $ps->{$_} = { sample_id => $self->{id_gen}->($self, "Sample_$_"), rank => $_ };
    }
    $self->{current_sample} = { in_file => '', out_file => '' };
}

sub end_tag_Sample
{
    my CATS::Problem::Parser $self = shift;
    my $ps = $self->{problem}->{samples};
    for my $s (@{$self->{current_samples}}) {
        for (qw(in_file out_file)) {
            if (exists $ps->{$s}->{$_}) {
                $self->error("Both src and inline data specified for sample $s $_")
                     if $self->{current_sample}->{$_} ne '';
            }
            else {
                $self->error("Neither src nor inline data specified for sample $s $_")
                     if $self->{current_sample}->{$_} eq '';
                $ps->{$s}->{$_} = $self->{current_sample}->{$_};
            }
        }
    }
    delete $self->{current_sample};
    delete $self->{current_samples};
}

sub sample_in_out
{
    my CATS::Problem::Parser $self = shift;
    my ($atts, $in_out) = @_;
    if ($atts->{src}) {
        my $ps = $self->{problem}->{samples};
        for (@{$self->{current_samples}}) {
            my $src = apply_test_rank($atts->{src}, $_);
            defined $ps->{$_}->{$in_out}
                and $self->error("Redefined attribute '$in_out' for sample $_");
            $ps->{$_}->{$in_out} =
                $self->{source}->read_member($src, "Invalid sample $in_out reference: '$src'");
        }
    }
    $self->{stml} = \$self->{current_sample}->{$in_out};
}

sub start_tag_SampleIn
{
    $_[0]->sample_in_out($_[1], 'in_file');
}

sub start_tag_SampleOut
{
    $_[0]->sample_in_out($_[1], 'out_file');
}

sub start_tag_Keyword
{
    (my CATS::Problem::Parser $self, my $atts) = @_;

    my $c = $atts->{code};
    !defined $self->{problem}{keywords}->{$c}
        or $self->warning("Duplicate keyword '$c'");
    $self->{problem}{keywords}->{$c} = 1;
}

sub start_tag_Run
{
    (my CATS::Problem::Parser $self, my $atts) = @_;
    my $m = $atts->{method};
    $self->error("Duplicate run method '$m'") if defined $self->{problem}{run_method};
    my %methods = (
        default => $cats::rm_default,
        interactive => $cats::rm_interactive,
        competitive => $cats::rm_competitive,
    );
    defined($self->{problem}{run_method} = $methods{$m})
        or $self->error("Unknown run method: '$m', must be one of: " . join ', ', keys %methods);

    $self->{problem}{run_method} == $cats::rm_competitive && !defined $atts->{players_count}
        and $self->error("Player count limit must be defined for competitive run method");

     $self->{problem}{run_method} != $cats::rm_competitive && defined $atts->{players_count}
        and $self->warning("Player count limit defined when run method is not competitive");

    $self->{problem}{players_count} = CATS::Testset::parse_simple_rank($atts->{players_count}, sub { $self->error(@_) })
        if $self->{problem}{run_method} == $cats::rm_competitive;

    $self->note("Run method set to '$m'");
}

sub parse_xml
{
    (my CATS::Problem::Parser $self, my $xml_file) = @_;
    $self->{tag_stack} = [];

    my $xml_parser = new XML::Parser::Expat;
    $xml_parser->setHandlers(
        Start => sub { $self->on_start_tag(@_) },
        End => sub { $self->on_end_tag(@_) },
        Char => sub { ${$self->{stml}} .= escape_xml($_[1]) if $self->{stml} },
        XMLDecl => sub { $self->{problem}{encoding} = $_[2] },
    );
    $xml_parser->parse($self->{source}->read_member($xml_file));
}

sub parse
{
    my $self = shift;
    $self->{source}->init;

    my @xml_members = $self->{source}->find_members('\.xml$');
    $self->error('*.xml not found') if !@xml_members;
    $self->error('found several *.xml in archive') if @xml_members > 1;

    $self->parse_xml($xml_members[0]);
    return $self->{problem};
}


1;
