package CATS::Problem::Backend;

use strict;
use warnings;

use Archive::Zip;

use File::Glob 'bsd_glob';
use File::Temp;

use JSON;

my $has_Http_Request_Common;
BEGIN { $has_Http_Request_Common = eval { require HTTP::Request::Common; import HTTP::Request::Common; 1; } }

sub new {
    my ($class, $problem, $log, $problem_path, $url, $login, $password, $action, $problem_exist, $root) = @_;
    $has_Http_Request_Common or $log->error('HTTP::Request::Common requires for update problem');
    my ($sid) = $url =~ m/sid=([a-zA-Z0-9]+)/ or $log->error("bad contest url $url");
    my ($cid) = $url =~ m/cid=([a-zA-Z0-9]+)/ or $log->error("bad contest url $url");
    my ($pid) = $url =~ m/download=([a-zA-Z0-9]+)/;
    my $self = {
        root => $root,
        problem => $problem,
        log => $log,
        name => $problem_exist ? $problem->{description}{title} : $problem_path,
        path => $problem_exist ? $problem_path : "$problem_path.zip",
        login => $login,
        password => $password,
        agent => LWP::UserAgent->new,
        sid => $sid,
        cid => $cid,
        pid => $pid,
        upload => $action eq 'upload',
    };
    return bless \%{$self} => $class;
}

sub login {
    my $self = shift;
    my $log = $self->{log};
    my $agent = $self->{agent};
    my $response = $agent->request(POST "$self->{root}/main.pl", [
        f => 'login',
        json => 1,
        login => $self->{login},
        passwd => $self->{password},
    ]);
    $response = decode_json($response->{_content});
    $response->{status} eq 'error' and $log->error($response->{message});
    $self->{sid} = $response->{sid};
}

sub start {
    my $self = shift;
    my $agent = $self->{agent};
    my $response = $agent->request(POST "$self->{root}/main.pl", [
        f => 'problems',
        json => 1,
        cid => $self->{cid},
        sid => $self->{sid},
    ]);
    $response = decode_json($response->{_content});
    if ($response->{error}) {
        $self->{log}->warning($response->{error});
        $self->login;
    }
}

sub upload_problem {
    my $self = shift;
    my $agent = $self->{agent};
    my $fname;
    if (-d $self->{path}) {
        my $zip = Archive::Zip->new;
        my $fh = File::Temp->new(SUFFIX => '.zip');
        $zip->addTree({ root => $self->{path} });
        $zip->writeToFileNamed($fh->filename);
        $fname = $fh->filename;
    } else {
        $fname = $self->{path};
    }

    my $response = $agent->request(POST "$self->{root}/main.pl",
        Content_Type => 'form-data',
        Content => [
            f => 'problems',
            json => 1,
            cid => $self->{cid},
            sid => $self->{sid},
            zip => [$fname],
            add_new => 1,
    ]);
}

sub download_without_using_url {
    my $self = shift;
    my $agent = $self->{agent};
    my $log = $self->{log};
    my $response = $agent->request(POST "$self->{root}/main.pl",
        Content  => [
            f => 'problems',
            json => 1,
            cid => $self->{cid},
            sid => $self->{sid},
        ]);
    $response = decode_json($response->{_content});
    my @problems = grep $_->{name} eq $self->{name}, @{$response->{problems}};
    @problems != 1 and $log->error(@problems . " problems have name '$self->{name}'");
    $agent->request(GET "$self->{root}/$problems[0]->{package_url}");
}

sub download_using_url {
    my $self = shift;
    my $agent = $self->{agent};
    my $response = $agent->request(GET "$self->{root}/main.pl", [
        sid => $self->{sid},
        cid => $self->{cid},
        f => 'problems',
        download => $self->{pid},
    ]);
    if ($response->{error}) {
        $self->{log}->warning($response->{error});
        $response = $self->download_without_using_url;
    }
    $response;
}

sub download_problem {
    my $self = shift;
    my $agent = $self->{agent};
    my $log = $self->{log};
    my $response = $self->{pid} ? $self->download_using_url : $self->download_without_using_url;
    my ($fname, $fh);
    -d $self->{path}
        ? $fname = ($fh = File::Temp->new(SUFFIX => '.zip'))->filename
        : open $fh, '>', $fname = $self->{path} or $log->error("Can't update $fname");
    binmode $fh;
    print $fh $response->{_content};
    close $fh;

    if (-d $self->{path}) {
        my $zip = Archive::Zip->new($fname) or die "Can't read $fname";
        for my $member ($zip->members) {
            $member->isDirectory and next;
            $member->fileName =~ m/[\\\/]?(.*)/;
            unlink my $fn = File::Spec->catfile($self->{path}, $1);
            $member->extractToFileNamed($fn);
        }
    }
}

sub update {
    my $self = shift;
    $self->start;
    $self->{upload} ? $self->upload_problem : $self->download_problem;
}

1;
