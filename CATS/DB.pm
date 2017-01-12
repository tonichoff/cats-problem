package CATS::DB;

use strict;
use warnings;

use Exporter qw(import);
our @EXPORT = qw($dbh $sql new_id _u);

use Carp;
use DBI;

use CATS::Config;

our ($dbh, $sql);


sub _u { splice(@_, 1, 0, { Slice => {} }); @_; }


sub select_row
{
    $dbh->selectrow_hashref(_u $sql->select(@_));
}


sub select_object
{
    my ($table, $condition) = @_;
    select_row($table, '*', $condition);
}


sub object_by_id
{
    my ($table, $id) = @_;
    select_object($table, { id => $id });
}

sub new_id
{
    return Digest::MD5::md5_hex(Encode::encode_utf8($_[1] // die)) unless $dbh;
    if ($CATS::Config::db_dsn =~ /Firebird/)
    {
        $dbh->selectrow_array(q~SELECT GEN_ID(key_seq, 1) FROM RDB$DATABASE~);
    }
    elsif ($CATS::Config::db_dsn =~ /Oracle/)
    {
        $dbh->selectrow_array(q~SELECT key_seq.nextval FROM DUAL~);
    }
    else
    {
        die 'Error in new_id';
    }
}

sub sql_connect
{
    my ($db_options) = @_;
    $dbh ||= DBI->connect(
        $CATS::Config::db_dsn, $CATS::Config::db_user, $CATS::Config::db_password,
        {
            AutoCommit => 0,
            LongReadLen => 1024*1024*20,
            FetchHashKeyName => 'NAME_lc',
            ib_enable_utf8 => 1,
            %$db_options,
        }
    );

    if (!defined $dbh)
    {
        die "Failed connection to SQL-server $DBI::errstr";
    }

    $dbh->{HandleError} = sub
    {
        my $m = "DBI error: $_[0]\n";
        croak $m;
        0;
    };

    $sql ||= SQL::Abstract->new if $SQL::Abstract::VERSION;
}


sub sql_disconnect
{
    $dbh or return;
    $dbh->disconnect;
    undef $dbh;
}


1;
