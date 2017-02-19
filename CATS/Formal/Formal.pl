use strict;
use warnings;

use Getopt::Long;
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use lib dirname(dirname(dirname(abs_path($0))));
use CATS::Formal::Formal;

my $generator = '';
my %from;
my %validate;
my $counter = 0;
my $to = \*STDOUT;
GetOptions(
    "generator=s" => \$generator,
    "from=s%{1,}" => sub {
        $from{$_[1]} = $_[2];
    },
    "to=s" => \$to,
    "validate=s%{1,}" => sub {
        $validate{$_[1]} = $_[2];
    }
);

if (keys %validate) {
    print CATS::Formal::Formal::validate(\%from, \%validate) || "validation ok";
} 

if ($generator) {
    print CATS::Formal::Formal::generate(\%from, $generator, $to) || "generation ok";
}

