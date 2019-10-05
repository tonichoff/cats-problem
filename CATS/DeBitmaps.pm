package CATS::DeBitmaps;

use strict;
use warnings;

use CATS::Constants;

sub extract_de_bitmap {
    map $_[0]->{"de_bits$_"}, 1..$cats::de_req_bitfields_count;
}

sub de_bitmap_str {
    my ($table) = @_;
    join ', ', map { join '.', $table, "de_bits$_" } 1..$cats::de_req_bitfields_count;
}

sub get_de_bitfields_hash {
    my @bitfields = @_;

    map { +"de_bits$_" => $bitfields[$_ - 1] || 0 } 1..$cats::de_req_bitfields_count;
}

1;
