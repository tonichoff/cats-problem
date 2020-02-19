package CATS::DB;

use strict;
use warnings;

use Exporter qw(import);
our @EXPORT = qw($dbh $sql new_id _u);
our @EXPORT_OK = qw(
    $BLOB_TYPE 
    current_sequence_value
    $FROM_DUMMY
    $KW_LIMIT
    next_sequence_value
    $TEXT_TYPE
);

use Carp;
use DBI;

use CATS::Config;

our ($dbh, $sql, $KW_LIMIT, $TEXT_TYPE, $BLOB_TYPE, $FROM_DUMMY);

sub _u { splice(@_, 1, 0, { Slice => {} }); @_; }

sub select_row {
    $dbh->selectrow_hashref(_u $sql->select(@_));
}

sub select_object {
    my ($table, $condition) = @_;
    select_row($table, '*', $condition);
}

sub object_by_id {
    my ($table, $id) = @_;
    select_object($table, { id => $id });
}

sub next_sequence_value {
    my ($seq) = @_;
    if ($CATS::Config::db_dsn =~ /Firebird/) {
        $dbh->selectrow_array(qq~SELECT GEN_ID($seq, 1) FROM RDB\$DATABASE~);
    }
    elsif ($CATS::Config::db_dsn =~ /Oracle/) {
        $dbh->selectrow_array(qq~SELECT $seq.nextval FROM DUAL~);
    }
    elsif ($CATS::Config::db_dsn =~ /Pg/) {
        $dbh->selectrow_array(qq~SELECT NEXTVAL('$seq')~);
    }
    else {
        die 'Error in next_sequence_value';
    }
}

sub current_sequence_value {
    my ($seq) = @_;
    if ($CATS::Config::db_dsn =~ /Firebird/) {
        $dbh->selectrow_array(qq~SELECT GEN_ID($seq, 0) FROM RDB\$DATABASE~);
    }
    elsif ($CATS::Config::db_dsn =~ /Pg/) {
        $dbh->selectrow_array(qq~SELECT LAST_VALUE FROM $seq~);
    }
    else {
        die 'Error in current_sequence_value';
    }
    }

sub new_id {
    return Digest::MD5::md5_hex(Encode::encode_utf8($_[1] // die)) unless $dbh;
    next_sequence_value('key_seq');
}

sub sql_connect {
    my ($db_options) = @_;

    if ($CATS::Config::db_dsn =~ /Firebird/) {
        $KW_LIMIT = 'ROWS';
        $FROM_DUMMY = 'FROM RDB$DATABASE';
        $BLOB_TYPE = 'BLOB';
        $TEXT_TYPE = 'BLOB SUB_TYPE TEXT';
    } elsif ($CATS::Config::db_dsn =~ /Pg/) {
        $KW_LIMIT = 'LIMIT';
        $FROM_DUMMY = '';
        $BLOB_TYPE = 'BYTEA';
        $TEXT_TYPE = 'TEXT';
    } else {
        die 'Error in sql_connect';
    }

    $dbh ||= DBI->connect(
        $CATS::Config::db_dsn, $CATS::Config::db_user, $CATS::Config::db_password,
        {
            AutoCommit => 0,
            LongReadLen => 1024*1024*20,
            FetchHashKeyName => 'NAME_lc',
            ib_enable_utf8 => 1,
            %$db_options,
        }
    ) or die "Failed connection to SQL-server $DBI::errstr";

    $dbh->{HandleError} = sub {
        my $m = "DBI error: $_[0]\n";
        croak $m;
        0;
    };

    $sql ||= SQL::Abstract->new if $SQL::Abstract::VERSION;
}

sub sql_disconnect {
    $dbh or return;
    $dbh->disconnect;
    undef $dbh;
}

sub catch_deadlock_error {
    my ($warn_prefix) = @_;
    my $err = $@ // '';
    # Firebird-specific message.
    $err =~ /concurrent transaction number is (\d+)/m or die $err;
    warn "$warn_prefix: deadlock with transaction: $1" if $warn_prefix;
    undef;
}

sub foreign_key_violation {
    # Firebird-specific message.
    $_[0] =~ /violation of FOREIGN KEY constraint "\w+" on table "(\w+)"/ && $1;
}

1;
