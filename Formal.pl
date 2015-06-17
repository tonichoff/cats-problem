use strict;
use warnings;

use Getopt::Long;
use Formal;
use Data::Dumper;

my $generator = '';
my %from;
my %to_validate;
my $counter = 0;
my $to = \*STDOUT;
GetOptions(
    "generator=s" => \$generator,
    "from=s%{1,}" => sub {
        $from{$_[1]} = $_[2];
    },
    "to=s" => \$to,
    "validate=s%{1,}" => sub {
        $to_validate{$_[1]} = $_[2];
    }
);

if (keys %to_validate) {
    print CATS::Formal::Formal::validate(\%from, \%to_validate) || "validation ok";
} 

if ($generator) {
    print CATS::Formal::Formal::generate(\%from, $generator, $to) || "generation ok";
}

