package CATS::JudgeDB;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB qw(new_id $dbh);

sub get_judge_id {
    my ($sid) = @_;
    $dbh->selectrow_array(q~
        SELECT J.id FROM judges J LEFT JOIN accounts A
        ON A.id = J.account_id WHERE A.sid = ?~, undef,
        $sid // '');
}

sub get_DEs {
    $dbh->selectall_arrayref(q~
        SELECT id, code, description, memory_handicap FROM default_de~, { Slice => {} });
}

sub get_problem {
    my ($pid) = @_;

    my $limits_str = join ', ', @cats::limits_fields;

    my $problem = $dbh->selectrow_hashref(qq~
        SELECT
            id, title, upload_date, $limits_str,
            input_file, output_file, std_checker, contest_id, formal_input,
            run_method, players_count, save_output_prefix
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
        SELECT generator_id, input_validator_id, rank, param, std_solution_id, in_file, out_file, gen_group
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
    $dbh->commit;
}

sub select_request {
    my ($p) = @_;

    $dbh->do(q~
        UPDATE judges SET is_alive = 1, alive_date = CURRENT_TIMESTAMP WHERE id = ?~, undef,
        $p->{jid}) if $p->{was_pinged} || $p->{time_since_alive} > $CATS::Config::judge_alive_interval / 24;
    $dbh->commit;

    return if $p->{pin_mode} == $cats::judge_pin_locked;

    my @params = ();
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

    my $req_id = $dbh->selectrow_hashref(qq~
        SELECT R.id
        FROM reqs R
        INNER JOIN contest_accounts CA ON CA.account_id = R.account_id AND CA.contest_id = R.contest_id
        LEFT JOIN contest_problems CP ON CP.contest_id = R.contest_id AND CP.problem_id = R.problem_id
        WHERE NOT EXISTS (
            SELECT 1
            FROM sources S
            INNER JOIN default_de DE ON DE.id = S.de_id
            WHERE (S.req_id = R.id OR EXISTS (
                SELECT 1 FROM
                req_groups RG
                WHERE RG.group_id = R.id AND RG.element_id = S.req_id)
            ) AND DE.code NOT IN ($p->{supported_DEs})
        )
        AND R.state = $cats::st_not_processed
        AND (CP.status <= $cats::problem_st_compile OR CA.is_jury = 1)
        AND ($pin_condition R.judge_id = ?) ROWS 1~, undef,
        @params) or return;

    my $element_req_ids = $dbh->selectcol_arrayref(q~
        SELECT RG.element_id as id
        FROM req_groups RG
        WHERE RG.group_id = ?~, { Slice => {} }, $req_id->{id});

    my $req_id_list = join ', ', ($req_id->{id}, @$element_req_ids);
    my $limits_fields = join ', ', map "CPL.$_ AS cp_$_, RL.$_ AS req_$_", @cats::limits_fields;

    my $sources_info = $dbh->selectall_arrayref(qq~
        SELECT
            R.id, R.problem_id, R.contest_id, R.state, CA.is_jury, C.run_all_tests,
            CP.status, CP.id as cpid, S.fname, S.src, S.de_id,
            $limits_fields
        FROM reqs R
        INNER JOIN contest_accounts CA ON CA.account_id = R.account_id AND CA.contest_id = R.contest_id
        INNER JOIN contests C ON C.id = R.contest_id
        LEFT JOIN sources S ON S.req_id = R.id
        LEFT JOIN default_de D ON D.id = S.de_id
        LEFT JOIN contest_problems CP ON CP.contest_id = R.contest_id AND CP.problem_id = R.problem_id
        LEFT JOIN limits CPL ON CPL.id = CP.limits_id
        LEFT JOIN limits RL ON RL.id = R.limits_id
        WHERE R.id IN ($req_id_list)~, { Slice => {} }) or return;

    my %sources_info_hash = map { $_->{id} => $_ } @$sources_info;

    my $req = $sources_info_hash{$req_id->{id}};

    $req->{element_reqs} = [];

    for my $element_req_id (@$element_req_ids) {
        push @{$req->{element_reqs}}, $sources_info_hash{$element_req_id};
    }

    if (@{$req->{element_reqs}} == 1) {
        my $element_req = $req->{element_reqs}->[0];
        $req->{problem_id} = $element_req->{problem_id};
        $req->{fname} = $element_req->{fname};
        $req->{src} = $element_req->{src};
        $req->{de_id} = $element_req->{de_id};
    } elsif (@{$req->{element_reqs}} > 1) {
        my $different_problem_ids = scalar grep $_->{problem_id} != $req->{problem_id}, @{$req->{element_reqs}};
        my $different_contests_ids = scalar grep $_->{contest_id} != $req->{contest_id}, @{$req->{element_reqs}};
        if ($different_problem_ids || $different_contests_ids) {
            warn 'group request and elements requests must be for the same problem and contest';
            $dbh->do(q~
                UPDATE reqs SET state = ?, judge_id = ? WHERE id = ?~, undef,
                $cats::st_unhandled_error, $p->{jid}, $req->{id});
            $dbh->commit;
            return;
        }
    }

    eval {
        $dbh->do(q~
            UPDATE reqs SET state = ?, judge_id = ? WHERE id = ?~, undef,
            $cats::st_install_processing, $p->{jid}, $req->{id});
        $dbh->commit;
        1;
    } and return $req;
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


1;
