package CATS::SourceManager;

use strict;
use warnings;

use File::Spec;
use Scalar::Util qw(looks_like_number);
use XML::Parser::Expat;

use CATS::BinaryFile;
use CATS::Constants;
use CATS::Utils qw(escape_xml);

sub get_tags() {{
    'id' => undef,
    'stype' => undef,
    'guid' => undef,
    'code' => undef,
    'memory_limit' => undef,
    'time_limit' => undef,
    'input_file' => undef,
    'output_file' => undef,
    'fname' => undef,
}}

sub on_end_tag {
    my ($source, $text, $p, $el, %atts) = @_;

    my $content = $$text;
    $$text = undef;
    $content =~ s/^\s+// if defined $content;

    if ($el eq 'path') {
        $source->{path} = $content;
        $source->{src} = '';
        CATS::BinaryFile::load($content, \$source->{src});
        return;
    }

    my @tags = grep $el eq $_, keys %{get_tags()};
    @tags == 1 or return;
    $content += 0 if looks_like_number($content);
    $source->{$el} = $content;
}

sub save {
    my ($source, $dir, $path) = @_;
    -d $dir or mkdir $dir or die "Unable to create $dir";
    $source->{guid} && $source->{guid} ne '' or return;
    my $fname = File::Spec->catfile($dir, "$source->{guid}.xml");
    {
        open my $fh, '>', $fname or die "Unable to open $fname for writing";
        print $fh qq~<?xml version="1.0"?>\n~;
        print $fh "<description>\n";
        for (keys %{get_tags()}) {
            print $fh "<$_>" . escape_xml($source->{$_}) . "</$_>\n" if defined $source->{$_};
        }
        print $fh "<path>$path</path>\n";
        print $fh "</description>\n";
    }
}

sub load {
    my ($guid, $dir) = @_;
    my $fname = File::Spec->catfile($dir, "$guid.xml");

    my $parser = XML::Parser::Expat->new;
    my $text = undef;
    my $source = {%{get_tags()}};
    $parser->setHandlers(
        End => sub { on_end_tag($source, \$text, @_) },
        Char => sub { $text .= $_[1] },
    );
    CATS::BinaryFile::load($fname, \my $data);
    $parser->parsefile($fname);
    return $source;
}

sub get_guids_by_regexp {
    my ($guid, $dir) = @_;
    $guid =~ s/\./\\./;
    $guid =~ s/\*/\.\*/;
    $guid = qr/$guid/;
    opendir my $dh, $dir or die "Cannot open directory: $!";
    map { /^(.*)\.xml$/ ? $1 : () } grep /^$guid/, readdir $dh;
}

1;
