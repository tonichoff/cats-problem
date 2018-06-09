package CATS::Problem::Source::Git;

use strict;
use warnings;

use File::Copy::Recursive qw(dircopy);
use File::Spec;
use File::Temp qw(tempdir);

use CATS::BinaryFile;
use CATS::Problem::Repository;

use base qw(CATS::Problem::Source::Base);

my $tmp_repo_template = 'repoXXXXXX';

sub new {
    my ($class, $link, $logger, $repo_path) = @_;
    $link or die 'No remote url specified!';
    $repo_path //= '';
    $repo_path .= '/' if $repo_path && $repo_path !~ m/\/$/;
    my %opts = (
        dir => undef,
        repo => undef,
        link => $link,
        logger => $logger,
        repo_path => $repo_path,
    );
    bless \%opts => $class;
}

sub get_zip {
    my $self = shift;
    my ($fname, $tree_id) = $self->{repo}->archive;
    my $zip;
    CATS::BinaryFile::load($fname, \$zip) or $self->error("getting zip archive failed: $!");
    $zip;
}

sub init {
    my $self = shift;
    my $tmpdir = tempdir($tmp_repo_template, TMPDIR => 1, CLEANUP => 1);
    $self->{dir} = $tmpdir;
    ($self->{repo}, my @log) =
        CATS::Problem::Repository::clone($self->{link}, "$tmpdir/", $self->{repo_path});
    $self->note(join "\n", @log);
}

sub find_members {
    my ($self, $regexp) = @_;
    map { s/^\Q$self->{repo_path}\E//; $_ } $self->{repo}->find_files($regexp);
}

sub read_member {
    my ($self, $name, $msg) = @_;
    my $fname = File::Spec->catfile($self->{repo}->get_problem_dir, $name);
    -f $fname or return $msg && $self->error($msg);
    CATS::BinaryFile::load($fname, \my $content);
    $content;
}

sub finalize {
    my ($self, $dbh, $repo, $problem, $message, $is_amend, $repo_id, $sha) = @_;

    dircopy($self->{dir}, $repo->get_dir);
}

1;
