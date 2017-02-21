use strict;
use warnings;

use File::Temp;
use FindBin;
use Test::More tests => 18;
use Test::Exception;

use lib '..';
use lib $FindBin::Bin;

use CATS::Problem::Source::Git;
use CATS::Problem::Source::PlainFiles;
use CATS::Problem::Source::Zip;

use ParserMockup;

my $logger = Logger->new;

sub prepare_dir {
    my ($tmpdir) = @_;
    for (qw(01 02 03)) {
        open my $f, '>', File::Spec->catfile($tmpdir, "$_.in");
        print $f $_ == 3 ? '0' : "data$_";
    }
}

sub check {
    my ($s, $name) = @_;

    $s->init;
    is_deeply [ sort $s->find_members(qr/\.in$/) ], [ qw(01.in 02.in 03.in) ], "$name find_members";
    is $s->read_member('02.in'), 'data02', "$name read_member";
    is $s->read_member('03.in', 'zzz'), '0', "$name read_member 0";
    is $s->read_member('04.in'), undef, "$name read_member nonexisting no error";
    throws_ok { $s->read_member('04.in', 'mymsg') } qr/mymsg/, "$name read_member nonexisting error";
}

{
    my $tmpdir = File::Temp->newdir or die;
    prepare_dir($tmpdir);
    throws_ok { CATS::Problem::Source::PlainFiles->new } qr 'dir', 'PlainFiles without dir';
    my $s = CATS::Problem::Source::PlainFiles->new(dir => $tmpdir, logger => $logger);
    check($s, 'PlainFiles');
}

{
    my $tmpdir = File::Temp->newdir or die;

    my $zip = Archive::Zip->new;
    $zip->addString("data$_", "$_.in") for qw(01 02);
    $zip->addString('0', '03.in');

    my $fn = File::Spec->catfile($tmpdir, 'test.zip');
    my $result = $zip->writeToFileNamed($fn);
    $result == Archive::Zip::AZ_OK or die;

    throws_ok { CATS::Problem::Source::Zip->new } qr 'filename', 'Zip without file';
    my $s = CATS::Problem::Source::Zip->new($fn, $logger);
    check($s, 'Zip');
}

SKIP: {
    my $tmpdir = File::Temp->newdir(CLEANUP => 1) or die;
    `git` or skip 'no git', 6;
    prepare_dir($tmpdir);
    my $gitdir = File::Spec->catfile($tmpdir, '.git');
    my $git = qq~git --git-dir="$gitdir" --work-tree="$tmpdir"~;
    `$git init`;
    `$git add $tmpdir/*`;
    `$git commit -m 'Init'`;

    throws_ok { CATS::Problem::Source::Git->new } qr 'No', 'Git without repo';
    my $s = CATS::Problem::Source::Git->new($tmpdir, $logger);
    check($s, 'Git');
}
