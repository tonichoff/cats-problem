package CATS::Problem;

use strict;
use warnings;

use CATS::Constants;

use fields qw(
    contest_id id description checker interactor statement constraints input_format output_format formal_input
    json_data explanation tests testsets samples keywords current_tests
    imports solutions generators validators visualizers modules pictures attachments encoding
    old_title replace repo has_checker run_method players_count snippets linters quizzes
);

sub new {
    my CATS::Problem $self = shift;
    my %args = @_;
    $self = fields::new($self) unless ref $self;
    $self->{$_} = $args{$_} for keys %args;
    return $self;
}

sub clear {
    my CATS::Problem $self = shift;
    undef $self->{$_} for keys %CATS::Problem::FIELDS;
    $self->{$_} = {} for qw(tests test_defaults testsets samples keywords);
    $self->{$_} = [] for qw(imports solutions generators validators visualizers modules pictures attachments linters);
}

sub checker_type_names() {{
    legacy => $cats::checker,
    testlib => $cats::testlib_checker,
    partial => $cats::partial_checker,
    multiple => $cats::multiple_checker,
}}

sub module_types() {{
    checker => $cats::checker_module,
    solution => $cats::solution_module,
    generator => $cats::generator_module,
    validator => $cats::validator_module,
    visualizer => $cats::visualizer_module,
    interactor => $cats::interactor_module,
    linter => $cats::linter_module,
}}

1;
