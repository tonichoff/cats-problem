package CATS::Job;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB;

sub create {
    my ($req_id, $type, $state, $fields) = @_;

    $fields ||= {};

    my $rid = new_id;

    $dbh->do(_u $sql->insert('jobs', {
        %$fields,
        id => $rid,
        req_id => $req_id,
        type => $type,
        state => $state,
        create_time => \'CURRENT_TIMESTAMP',
    })) or return;

    $dbh->do(q~
        INSERT INTO jobs_queue (id) VALUES (?)~, undef,
        $rid) or return;

    $rid;
}

1;
