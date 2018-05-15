package cats;

$anonymous_login = 'anonymous';

@langs = qw(ru en cn);

# Values problem_sources.stype.
$generator = 0;
$solution = 1;
$checker = 2;
$adv_solution = 3;
$generator_module = 4;
$solution_module = 5;
$checker_module = 6;
$testlib_checker = 7;
$partial_checker = 8;
$validator = 9;
$validator_module = 10;
$visualizer = 11;
$visualizer_module = 12;
$interactor = 13;
$interactor_module = 14;
$multiple_checker = 15;

%source_module_names = (
    $generator => 'generator',
    $solution => 'solution',
    $checker => 'checker (deprecated)',
    $adv_solution => 'solution (autorun)',
    $generator_module => 'generator module',
    $solution_module => 'solution module',
    $checker_module => 'checker module',
    $testlib_checker => 'checker',
    $partial_checker => 'partial checker',
    $validator => 'validator',
    $validator_module => 'validator module',
    $visualizer => 'visualizer',
    $visualizer_module => 'visualizer module',
    $interactor => 'interactor',
    $interactor_module => 'interactor module',
    $multiple_checker => 'multiple checker',
);

# Map source types to module types.
%source_modules = (
    $generator => $generator_module,
    $solution => $solution_module,
    $adv_solution => $solution_module,
    $checker => $checker_module,
    $testlib_checker => $checker_module,
    $partial_checker => $checker_module,
    $validator => $validator_module,
    $visualizer => $visualizer_module,
    $interactor => $interactor_module,
    $multiple_checker => $checker_module,
);

# Values for jobs.state.
$job_st_waiting = 0;
$job_st_in_progress = 1;
$job_st_finished = 2;

# Values for jobs.type.
$job_type_submission = 1;
$job_type_generate_snippets = 2;

# Values for reqs.state.
$st_not_processed = 0;
$st_unhandled_error = 1;
$st_install_processing = 2;
$st_testing = 3;
$st_awaiting_verification = 4;

# This value should not actually exist in the database.
# Values greater than this indicate that judge has finished processing.
$request_processed = 9;

$st_accepted = 10;
$st_wrong_answer = 11;
$st_presentation_error = 12;
$st_time_limit_exceeded = 13;
$st_runtime_error = 14;
$st_compilation_error = 15;
$st_security_violation = 16;
$st_memory_limit_exceeded = 17;
$st_ignore_submit = 18;
$st_idleness_limit_exceeded = 19;
$st_manually_rejected = 20;
$st_write_limit_exceeded = 21;

# Values for contest_problems.status. Order is important:
$problem_st_manual    = 0; # Requre manual verification after judge acceptance.
$problem_st_ready     = 1; # Judges runs solutions at or above this status.
$problem_st_compile   = 2; # Judges process runs starting at or above this status.
$problem_st_suspended = 3; # UI accepts submissions at or above this status.
$problem_st_disabled  = 4; # UI displays problems at or above this status.
$problem_st_hidden    = 5;

# Values for problems.run_method.
$rm_default = 0;
$rm_interactive = 1;
$rm_competitive = 2;

$penalty = 20;

@problem_codes = ('A'..'Z', '1'..'9');
sub is_good_problem_code { $_[0] =~ /^[A-Z1-9]$/ }

# Length of test file prefix displayed to user.
$test_file_cut = 30;

$log_section_start_prefix = '>====== ';
$log_section_end_prefix = '<====== ';
$log_section_compile = 'compile';

@limits_fields = qw(time_limit memory_limit write_limit save_output_prefix);

$judge_pin_locked  = 0;
$judge_pin_req     = 1;
$judge_pin_contest = 2;
$judge_pin_any     = 3;

# de_bits* bitfields in reqs table
$de_req_bitfields_count = 2;
$de_req_bitfield_size = 62;

# WebApi error strings
$es_old_de_version = 'old de version';

1;
