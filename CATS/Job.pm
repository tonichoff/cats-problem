package CATS::Job;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB;

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

    create($type, { %$fields, testsets => $_ }) for @$testsets;
}

1;
