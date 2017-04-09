use strict;
use warnings;

use Getopt::Long;
use File::Basename;
use File::Spec;
use File::Slurp;
use Cwd qw(abs_path);
use lib dirname(dirname(dirname(abs_path($0))));
use CATS::Formal::Formal;
use Data::Dump qw(dump);
use List::Util 'first';
use Module::Load;


my $selected_generator = '';
my %from;
my %validate;
my $counter = 0;
my $to = \*STDOUT;
GetOptions(
    "generator=s" => \$selected_generator,
    "from=s%{1,}" => sub {
        $from{$_[1]} = $_[2];
    },
    "to=s" => \$to,
    "validate=s%{1,}" => sub {
        $validate{$_[1]} = $_[2];
    }
);


for my $key (keys %from) {
    $from{$key} = read_file($from{$key});
}
for my $key (keys %validate) {
    $validate{$key} = read_file($validate{$key});
}

my $generators_dir = File::Spec->catfile(dirname(abs_path($0)), "Generators");
opendir(DH, $generators_dir);
my @generator_sources = readdir(DH);
closedir(DH);
my @generators = ();
for my $generator_source (@generator_sources) {
    next unless ($generator_source =~ /\.pm$/);
    my ($source_name) = fileparse($generator_source, ".pm");
    my $generator_package = "CATS::Formal::Generators::$source_name";
    load $generator_package;
    my $id = $generator_package->can("id") && $generator_package->id || next;
    push @generators, { id => $id, package => $generator_package };
}

if (keys %validate) {
    print CATS::Formal::Formal::validate(\%from, \%validate) || "validation ok";
}


if ($selected_generator) {
    my $generator = first {$_->{id} eq $selected_generator} @generators;
    $generator || die "unknown generator $selected_generator\n";
    my $result = CATS::Formal::Formal::generate($generator->{package}->new(), %from);
    $result || die CATS::Formal::Error::get();
    #write $result to $to
    write_file($to, $result);
}

1;