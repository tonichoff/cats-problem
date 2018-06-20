package CATS::Job;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB;

sub create_or_replace {
    my ($type, $fields) = @_;

    $dbh->selectrow_array(qq~
        SELECT COUNT(*) FROM jobs
        WHERE state = $cats::job_st_waiting AND type = $cats::job_type_submission AND
            req_id = ?~, undef,
        $fields->{req_id}) and return;

    for (1..4) {
        my $job_ids = $dbh->selectcol_arrayref(q~
            SELECT id FROM jobs WHERE finish_time IS NULL AND req_id = ?~, undef,
            $fields->{req_id});
        @$job_ids or return create($type, $fields);
        grep cancel($_), @$job_ids or $dbh->commit;
    }
    die;
}

sub is_canceled {
    my ($job_id) = @_;

    my ($st) = $dbh->selectrow_array(q~
        SELECT state FROM jobs WHERE id = ?~, undef,
        $job_id);

    $st == $cats::job_st_canceled;
}

sub cancel {
    my ($job_id) = @_;

    $dbh->do(q~
        DELETE FROM jobs_queue WHERE id = ?~, undef,
        $job_id);

    finish($job_id, $cats::job_st_canceled);
}

sub finish {
    my ($job_id, $job_state) = @_;

    eval {
        ($dbh->do(q~
            UPDATE jobs SET state = ?, finish_time = CURRENT_TIMESTAMP
            WHERE id = ? AND finish_time IS NULL~, undef,
            $job_state, $job_id) // 0) > 0 or return;
        $dbh->commit;
        1;
    } or CATS::DB::catch_deadlock_error('finish_job');
}

sub create {
    my ($type, $fields) = @_;

    $fields ||= {};
    $fields->{state} ||= $cats::job_st_waiting;
    my $rid = new_id;

    $fields->{start_time} = \'CURRENT_TIMESTAMP' if $fields->{state} == $cats::job_st_in_progress;
    $dbh->do(_u $sql->insert('jobs', {
        %$fields,
        id => $rid,
        type => $type,
        create_time => \'CURRENT_TIMESTAMP',
    })) or return;

    if ($fields->{state} == $cats::job_st_waiting) {
        $dbh->do(q~
            INSERT INTO jobs_queue (id) VALUES (?)~, undef,
            $rid) or return;
    }

    $rid;
}

sub create_splitted_jobs {
    my ($type, $testsets, $fields) = @_;

    $fields ||= {};
    $fields->{state} ||= $cats::job_st_waiting;

    is_canceled($fields->{parent_id}) and return;

    create($type, { %$fields, testsets => $_ }) for @$testsets;
}

1;
