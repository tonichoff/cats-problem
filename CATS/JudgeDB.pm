package CATS::JudgeDB;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB qw(new_id $dbh);
use CATS::DevEnv;

sub get_judge_id {
    my ($sid) = @_;
    $dbh->selectrow_array(q~
        SELECT J.id FROM judges J LEFT JOIN accounts A
        ON A.id = J.account_id WHERE A.sid = ?~, undef,
        $sid // '');
}

sub get_DEs {
    my ($p) = @_;
    my $condition = join ' AND ', ($p->{active_only} ? ('in_contests = 1') : ()), ($p->{id} ? ('id = ?') : ());
    $condition = 'WHERE ' . $condition if $condition;
    {
        des => $dbh->selectall_arrayref(qq~
            SELECT id, code, description, file_ext, default_file_ext
            FROM default_de
            $condition ORDER BY code~, { Slice => {} },
            $p->{id} ? ($p->{id}) : ()),
        version => current_de_version()
    }
}

sub get_problem {
    my ($pid) = @_;

    my $limits_str = join ', ', @cats::limits_fields;

    my $problem = $dbh->selectrow_hashref(qq~
        SELECT
            id, title, upload_date, $limits_str,
            input_file, output_file, std_checker, contest_id, formal_input,
            run_method, players_count, save_output_prefix, save_input_prefix, save_answer_prefix
        FROM problems WHERE id = ?~, { Slice => {}, ib_timestampformat => '%d-%m-%Y %H:%M:%S' }, $pid);
    $problem->{run_method} //= $cats::rm_default;
    $problem;
}

sub get_problem_sources {
    my ($pid) = @_;
    my $problem_sources = $dbh->selectall_arrayref(q~
        SELECT ps.*, dd.code FROM problem_sources ps
            INNER JOIN default_de dd ON dd.id = ps.de_id
        WHERE ps.problem_id = ? ORDER BY ps.id~, { Slice => {} },
        $pid);
    my $imported = $dbh->selectall_arrayref(q~
        SELECT ps.*, dd.code FROM problem_sources ps
            INNER JOIN default_de dd ON dd.id = ps.de_id
            INNER JOIN problem_sources_import psi ON ps.guid = psi.guid
        WHERE psi.problem_id = ? ORDER BY ps.id~, { Slice => {} },
        $pid);
    $_->{is_imported} = 1 for @$imported;
    [ @$problem_sources, @$imported ];
}

sub get_problem_tests {
    my ($pid) = @_;

    $dbh->selectall_arrayref(q~
        SELECT
            generator_id, input_validator_id, rank, param, std_solution_id,
            CASE WHEN in_file_size  IS NULL THEN in_file  ELSE NULL END AS in_file,
            CASE WHEN out_file_size IS NULL THEN out_file ELSE NULL END AS out_file,
            in_file_size,
            out_file_size,
            gen_group
        FROM tests WHERE problem_id = ? ORDER BY rank~, { Slice => {} },
        $pid);
}

sub is_problem_uptodate {
    my ($pid, $date) = @_;

    scalar $dbh->selectrow_array(q~
        SELECT 1 FROM problems
        WHERE id = ? AND upload_date - 1.0000000000 / 24 / 60 / 60 <= ?~, undef,
        $pid, $date);
}

sub save_log_dump {
    my ($req_id, $dump) = @_;

    my $id = $dbh->selectrow_array(q~
        SELECT id FROM log_dumps WHERE req_id = ?~, undef,
        $req_id);
    if (defined $id) {
        my $c = $dbh->prepare(q~UPDATE log_dumps SET dump = ? WHERE id = ?~);
        $c->bind_param(1, $dump, { ora_type => 113 });
        $c->bind_param(2, $id);
        $c->execute;
    }
    else {
        my $c = $dbh->prepare(q~INSERT INTO log_dumps (id, dump, req_id) VALUES (?, ?, ?)~);
        $c->bind_param(1, new_id);
        $c->bind_param(2, $dump, { ora_type => 113 });
        $c->bind_param(3, $req_id);
        $c->execute;
    }
}

sub copy_req_tree_info {
    my ($req_tree, @reqs) = @_;
    for my $req (@reqs) {
        $req_tree->{$req->{id}}->{$_} = $req->{$_} for keys %$req;
    }
}

sub add_info_to_req_tree {
    my ($needed_info, $req_ids, $req_tree) = @_;

    $needed_info //= {};
    $req_tree //= {};

    my $needed_fields = join ', ', qw(R.id R.elements_count), @{$needed_info->{fields} // []};
    my $needed_tables = join ' ', @{$needed_info->{tables} // []};
    my $req_ids_list = join ', ', $req_ids ? @$req_ids : keys %$req_tree or return {};

    warn "add_info_to_req_tree. $req_ids_list";

    my $reqs = $dbh->selectall_arrayref(qq~
        SELECT $needed_fields
        FROM reqs R
            $needed_tables
        WHERE R.id IN ($req_ids_list)~, { Slice => {} });

    copy_req_tree_info($req_tree, @$reqs);

    $req_tree;
}

sub get_req_tree {
    my ($req_ids, $p, $req_tree) = @_;

    $req_ids && @$req_ids or return {};
    $req_tree //= {};

    warn 'get_req_tree. given ids: ', join ', ', @$req_ids;

    my $level_req_tree = add_info_to_req_tree($p, $req_ids);

    my @reqs_to_next_level = grep {
        $_->{elements_count} &&
        !defined $req_tree->{$_->{id}} &&
        (!$p->{on_level_filter} || $p->{on_level_filter}->($_))
    } values %$level_req_tree;

    copy_req_tree_info($req_tree, values %$level_req_tree);

    warn 'get_req_tree. filtered to next level: ', join ', ', map $_->{id}, @reqs_to_next_level;

    @reqs_to_next_level or return $req_tree;

    my $req_ids_to_next_level_list = join ', ', map $_->{id}, @reqs_to_next_level;
    my $req_elements = $dbh->selectall_arrayref(qq~
        SELECT RG.group_id, RG.element_id
        FROM req_groups RG
        WHERE RG.group_id IN ($req_ids_to_next_level_list)~, { Slice => {} });

    for my $req_element (@$req_elements) {
        warn "get_req_tree. link: $req_element->{group_id}->$req_element->{element_id}";
        $req_tree->{$req_element->{element_id}} //= {};
        #push @{$req_tree->{$req_element->{element_id}}->{parents} //= []}, $req_tree->{$req_element->{group_id}};
        push @{$req_tree->{$req_element->{group_id}}->{elements} //= []}, $req_tree->{$req_element->{element_id}};
    }

    for my $req (@reqs_to_next_level) {
        if (@{$req_tree->{$req->{id}}->{elements} //= []} != $req->{elements_count}) {
            die "elements_count mismatch on request: $req->{id}";
        }
    }

    my @unvisited_ids = grep !defined $req_tree->{$_}->{id}, map $_->{element_id}, @$req_elements;
    return @unvisited_ids ? get_req_tree(\@unvisited_ids, $p, $req_tree) : $req_tree;
}

sub ensure_request_de_bitmap_cache {
    my ($req_ids, $dev_env, $select_all) = @_;

    $req_ids or return {};

    if (!ref($req_ids)) {
        $req_ids = [ $req_ids ];
    } elsif (ref($req_ids) ne 'ARRAY') {
        die 'req_ids is not neither reference to ARRAY or scalar';
    }

    @$req_ids or return {};

    $dev_env //= CATS::DevEnv->new(get_DEs);

    my $req_tree = get_req_tree($req_ids, {
        fields => [
            'S.de_id',
            'RDEBC.version as de_version',
            de_bitmap_str('RDEBC'),
        ],
        tables => [
            'LEFT JOIN req_de_bitmap_cache RDEBC ON RDEBC.req_id = R.id',
            'LEFT JOIN sources S ON S.req_id = R.id',
        ],
        on_level_filter => $select_all ? undef : sub {
            !$dev_env->is_good_version($_[0]->{de_version});
        },
    });

    my @needed_update_reqs;
    my $collect_needed_update_req_ids;
    $collect_needed_update_req_ids = sub {
        my $req = shift;

        my @bitmap;

        if (!$dev_env->is_good_version($req->{de_version})) {
            if ($req->{elements_count} > 0) {
                warn "ensure_request_de_bitmap_cache. req $req->{id} needs update recursively";
                @bitmap = (0) x $cats::de_req_bitfields_count;
                for my $req_element (@{$req->{elements}}) {
                    my @element_bitmap = $collect_needed_update_req_ids->($req_element);
                    $bitmap[$_] |= $element_bitmap[$_] for 0..$cats::de_req_bitfields_count-1;
                }
            } else {
                warn "ensure_request_de_bitmap_cache. req $req->{id} needs update";
                @bitmap = $dev_env->bitmap_by_ids($req->{de_id});
            }
            my %de_bitfields_hash = get_de_bitfields_hash(@bitmap);
            $req->{$_} = $de_bitfields_hash{$_} for keys %de_bitfields_hash;
            $req->{bitmap} = [ @bitmap ];
            push @needed_update_reqs, $req;
        } else {
            @bitmap = extract_de_bitmap($req);
        }

        warn "ensure_request_de_bitmap_cache. req $req->{id} is up to date";

        @bitmap;
    };

    $collect_needed_update_req_ids->($req_tree->{$_}) for @$req_ids;

    @needed_update_reqs or return $req_tree;

    my $update_req_ids_list = join ', ', map $_->{id}, @needed_update_reqs;
    $dbh->do(qq~
        DELETE FROM req_de_bitmap_cache RDEBC
        WHERE RDEBC.req_id IN ($update_req_ids_list)~);

    my $set_bitmap_cache_str = join ', ', map "de_bits$_", 1..$cats::de_req_bitfields_count;
    my $q_str = join ', ', map '?', 1..$cats::de_req_bitfields_count;
    my $c = $dbh->prepare(qq~
        INSERT INTO req_de_bitmap_cache (req_id, version, $set_bitmap_cache_str) VALUES (?, ?, $q_str)~);

    $c->execute($_->{id}, $dev_env->version, @{$_->{bitmap}}) for @needed_update_reqs;

    if ($dev_env->is_good_version(current_de_version())) {
        $dbh->commit;
        warn 'ensure_request_de_bitmap_cache. updated reqs: ', join ', ', map $_->{id}, @needed_update_reqs;
    } else {
        $dbh->rollback;
        warn 'ensure_request_de_bitmap_cache. concurrent de change detected. trying again';
        goto &ensure_request_de_bitmap_cache;
    }

    $req_tree;
}

sub extract_de_bitmap {
    map $_[0]->{"de_bits$_"}, 1..$cats::de_req_bitfields_count;
}

sub de_bitmap_str {
    my ($table) = @_;
    join ', ', map { join '.', $table, "de_bits$_" } 1..$cats::de_req_bitfields_count;
}

sub get_de_bitfields_hash {
    my @bitfields = @_;

    map { +"de_bits$_" => $bitfields[$_ - 1] || 0 } 1..$cats::de_req_bitfields_count;
}

sub current_de_version {
    $dbh->selectrow_array(q~
        SELECT GEN_ID(de_bitmap_cache_seq, 0) FROM RDB$DATABASE~);
}

sub ensure_problem_de_bitmap_cache {
    my ($problem_id, $dev_env) = @_ or return;

    $dev_env //= CATS::DevEnv->new(get_DEs);

    my ($problem_de_version) = $dbh->selectrow_array(q~
        SELECT PDEBC.version
        FROM problems P
            LEFT JOIN problem_de_bitmap_cache PDEBC ON PDEBC.problem_id = P.id
        WHERE P.id = ?~, { Slice => {} },
        $problem_id);

    return if $problem_de_version && $dev_env->version == $problem_de_version;

    my $de_ids = $dbh->selectcol_arrayref(q~
        SELECT de_id FROM problem_sources
        WHERE problem_id = ?~, undef,
        $problem_id);

    warn $problem_de_version
        ? 'ensure_problem_de_bitmap_cache. update existing debc'
        : 'ensure_problem_de_bitmap_cache. create new problem debc';

    my @de_bitmap = $dev_env->bitmap_by_ids(@$de_ids);
    my $update_debc_str = join ', ', map "de_bits$_ = ?", 1..$cats::de_req_bitfields_count;
    my $insert_debc_str = join ', ', map "de_bits$_", 1..$cats::de_req_bitfields_count;
    my $q_str = join ', ', map '?', 1..$cats::de_req_bitfields_count;
    my $sql = !defined $problem_de_version
    ? qq~
        INSERT INTO problem_de_bitmap_cache (
            version, $insert_debc_str, problem_id
        ) VALUES (
            ?, $q_str, ?
        )~
    : qq~
        UPDATE problem_de_bitmap_cache
            SET version = ?, $update_debc_str
        WHERE problem_id = ?~;
    $dbh->do($sql, undef, $dev_env->version, @de_bitmap, $problem_id);

    $dbh->commit;

    warn 'new problem de bits: ', join ', ', @de_bitmap;

    return \@de_bitmap;
}

sub invalidate_de_bitmap_cache {
    $dbh->do(q~
        DELETE FROM req_de_bitmap_cache~);
    $dbh->do(q~
        DELETE FROM problem_de_bitmap_cache~);
    $dbh->selectrow_array(q~
        SELECT NEXT VALUE FOR de_bitmap_cache_seq FROM RDB$DATABASE~);
    $dbh->commit;
}

sub set_request_state {
    my ($p) = @_;

    $dbh->do(q~
        UPDATE reqs SET state = ?, failed_test = ?, result_time = CURRENT_TIMESTAMP
        WHERE id = ? AND judge_id = ?~, undef,
        $p->{state}, $p->{failed_test}, $p->{req_id}, $p->{jid});
    if ($p->{state} == $cats::st_unhandled_error && defined $p->{problem_id} && defined $p->{contest_id}) {
        $dbh->do(q~
            UPDATE contest_problems SET status = ?
            WHERE problem_id = ? AND contest_id = ? AND status < ?~, undef,
            $cats::problem_st_suspended, $p->{problem_id}, $p->{contest_id}, $cats::problem_st_suspended);
    }
    $dbh->do(q~
        DELETE FROM req_de_bitmap_cache WHERE req_id = ?~, undef,
        $p->{req_id}); # Clear cache to save space after testing.
    $dbh->commit;
}

sub select_request {
    my ($p) = @_;

    $dbh->do(q~
        UPDATE judges SET is_alive = 1, alive_date = CURRENT_TIMESTAMP WHERE id = ?~, undef,
        $p->{jid}) if $p->{was_pinged} || $p->{time_since_alive} > $CATS::Config::judge_alive_interval / 24;
    $dbh->commit;

    return if $p->{pin_mode} == $cats::judge_pin_locked;

    my $dev_env = CATS::DevEnv->new(get_DEs);
    return { error => $cats::es_old_de_version } if !$dev_env->is_good_version($p->{de_version});

    my $des_cond_fmt = sub {
        my ($table) = @_;
        my $cond =
            join ' AND ', map "BIN_AND($table.de_bits$_, ?) = $table.de_bits$_",
                1..$cats::de_req_bitfields_count;
        qq~
        (CASE
            WHEN $table.version IS NULL THEN 1
            WHEN $table.version = ? THEN (CASE WHEN $cond THEN 1 ELSE 0 END)
            ELSE 1
        END) = 1~;
    };
    my $des_condition = $des_cond_fmt->('RDEBC') . ' AND ' . $des_cond_fmt->('PDEBC');

    my @params = ($dev_env->version, extract_de_bitmap($p)) x 2;

    my $pin_condition = '';

    if ($p->{pin_mode} == $cats::judge_pin_contest) {
        $pin_condition =
            'EXISTS (
                SELECT 1
                FROM contest_accounts CA
                INNER JOIN judges J ON CA.account_id = J.account_id
                WHERE R.contest_id = CA.contest_id AND J.id = ?
            ) AND R.judge_id IS NULL OR';
        push @params, $p->{jid};
    }
    elsif ($p->{pin_mode} == $cats::judge_pin_any) {
        $pin_condition = 'R.judge_id IS NULL OR';
    }

    push @params, $p->{jid};

    my $sel_req = $dbh->selectrow_hashref(qq~
        SELECT R.id, R.problem_id, R.elements_count, RDEBC.version AS request_de_version, PDEBC.version AS problem_de_version
        FROM reqs R
            INNER JOIN contest_accounts CA ON CA.account_id = R.account_id AND CA.contest_id = R.contest_id
            LEFT JOIN contest_problems CP ON CP.contest_id = R.contest_id AND CP.problem_id = R.problem_id
            INNER JOIN problems P ON P.id = R.problem_id
            LEFT JOIN req_de_bitmap_cache RDEBC ON RDEBC.req_id = R.id
            LEFT JOIN problem_de_bitmap_cache PDEBC ON PDEBC.problem_id = P.id
        WHERE
            R.state = $cats::st_not_processed AND
            (CP.status <= $cats::problem_st_compile OR CA.is_jury = 1) AND
            $des_condition AND
            ($pin_condition R.judge_id = ?) ROWS 1~, undef,
        @params) or return;

    if (!$dev_env->is_good_version($sel_req->{problem_de_version})) {
        return if $sel_req->{problem_de_version} && $sel_req->{problem_de_version} > $dev_env->version;
        warn "update problem de cache: $sel_req->{id}";
        my $updated_de = ensure_problem_de_bitmap_cache($sel_req->{problem_id}, $dev_env, 1);
        if (!CATS::DevEnv::check_supported($updated_de, [ extract_de_bitmap($p) ])) {
            warn "can't check this problem";
            return;
        }
    }

    my $req_tree;

    if (!$dev_env->is_good_version($sel_req->{request_de_version})) {
        return if $sel_req->{request_de_version} && $sel_req->{request_de_version} > $dev_env->version;
        warn "update request de cache: $sel_req->{id}";
        $req_tree = ensure_request_de_bitmap_cache($sel_req->{id}, $dev_env);
        my $updated_de = $req_tree->{$sel_req->{id}}->{bitmap};
        if (!CATS::DevEnv::check_supported($updated_de, [ extract_de_bitmap($p) ])) {
            warn "can't check this request";
            return;
        }
    } else {
        $req_tree = $sel_req->{elements_count} ?
            get_req_tree([ $sel_req->{id} ]) :
            { $sel_req->{id} => $sel_req };
    }

    add_info_to_req_tree({
        fields => [
            qw(R.id R.problem_id R.contest_id R.state CA.is_jury C.run_all_tests
            CP.status S.fname S.src S.de_id), 'CP.id as cpid',
            map "CPL.$_ AS cp_$_, RL.$_ AS req_$_", @cats::limits_fields
        ],
        tables => [
            'INNER JOIN contest_accounts CA ON CA.account_id = R.account_id AND CA.contest_id = R.contest_id',
            'INNER JOIN contests C ON C.id = R.contest_id',
            'LEFT JOIN sources S ON S.req_id = R.id',
            'LEFT JOIN default_de D ON D.id = S.de_id',
            'LEFT JOIN contest_problems CP ON CP.contest_id = R.contest_id AND CP.problem_id = R.problem_id',
            'LEFT JOIN limits CPL ON CPL.id = CP.limits_id',
            'LEFT JOIN limits RL ON RL.id = R.limits_id',
        ],
    }, undef, $req_tree);

    my $check_req;
    $check_req = sub {
        my ($req, $level) = @_;
        $level //= 0;

        if ($level > 2) {
            warn 'request group is too deep';
            return 0;
        }

        if($req->{elements_count} == 1) {
            my $element_req = $req->{elements}->[0];
            $check_req->($element_req, $level + 1) or return 0;
            $req->{$_} = $element_req->{$_} for qw(problem_id fname src de_id);
        } elsif ($req->{elements_count} > 1) {
            if ($level != 0) {
                warn 'group has too many elements ot its level';
                return 0;
            }
            my $different_problem_ids = scalar grep $_->{problem_id} != $req_tree->{$sel_req->{id}}->{problem_id}, @{$req->{elements}};
            my $different_contests_ids = scalar grep $_->{contest_id} != $req_tree->{$sel_req->{id}}->{contest_id}, @{$req->{elements}};
            if ($different_problem_ids || $different_contests_ids) {
                warn 'group request and elements requests must be for the same problem and contest';
                return 0;
            }
            $check_req->($_, $level + 1) or return 0 for @{$req->{elements}};
        }

        return 1;
    };

    eval {
        my $set_state = sub {
            $dbh->do(q~
                UPDATE reqs SET state = ?, judge_id = ? WHERE id = ?~, undef,
                $_[0], $p->{jid}, $sel_req->{id});
            $dbh->commit;
        };
        if (!$check_req->($req_tree->{$sel_req->{id}})) {
            $set_state->($cats::st_unhandled_error);
            return;
        } else {
            $set_state->($cats::st_install_processing);
        }
        1;
    } and return $req_tree->{$sel_req->{id}};
    my $err = $@ // '';
    $err =~ /concurrent transaction number is (\d+)/m or die $err;
    # Another judge has probably acquired this problem concurrently.
    warn "select_request: deadlock with transaction: $1";
    undef;
}

sub delete_req_details {
    my ($req_id) = @_;

    $dbh->do(q~DELETE FROM req_details WHERE req_id = ?~, undef, $req_id);
    $dbh->commit;
}

sub insert_req_details {
    my (%p) = @_;

    my ($output, $output_size) = map $p{$_}, qw(output output_size);
    delete $p{$_} for qw(output output_size);

    $dbh->do(
        sprintf(
            q~INSERT INTO req_details (%s) VALUES (%s)~,
            join(', ', keys %p), join(', ', ('?') x keys %p)
        ),
        undef, values %p
    );

    $dbh->do(q~
        INSERT INTO solution_output (req_id, test_rank, output, output_size, create_time) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)~, undef,
        $p{req_id}, $p{test_rank}, $output, $output_size) if $output_size;

    $dbh->commit;
}

sub save_input_test_data {
    my ($problem_id, $test_rank, $input, $input_size) = @_;

    $dbh->do(q~
        UPDATE tests SET in_file = ?, in_file_size = ?
            WHERE problem_id = ? AND rank = ? AND in_file IS NULL~, undef,
        $input, $input_size, $problem_id, $test_rank);

    $dbh->commit;
}

sub save_answer_test_data {
    my ($problem_id, $test_rank, $answer, $answer_size) = @_;

    $dbh->do(q~
        UPDATE tests SET out_file = ?, out_file_size = ?
            WHERE problem_id = ? AND rank = ? AND out_file IS NULL~, undef,
        $answer, $answer_size, $problem_id, $test_rank);

    $dbh->commit;
}

1;
