package CATS::DevEnv;

use strict;
use warnings;

use fields qw(_des _de_version);

use CATS::Constants;
use CATS::Utils;

sub new {
    my ($self, $p) = @_;
    $self = fields::new($self) unless ref $self;

    $self->{_des} = [ sort { $a->{code} <=> $b->{code} } @{$p->{des}} ];
    my $i = 0;
    $_->{index} = $i++ for @{$self->{_des}};

    $self->{_de_version} = $p->{version};

    return $self;
}

sub split_exts { split /\;/, $_[0]->{file_ext} }

sub by_file_extension {
    my ($self, $file_name) = @_;
    $file_name or return;

    my (undef, undef, undef, undef, $ext) = CATS::Utils::split_fname(lc $file_name);

    for my $de (@{$self->des}) {
        grep { return $de if $_ eq $ext } split_exts($de);
    }

    undef;
}

sub by_code {
    my ($self, $code) = @_;
    my @r = grep $_->{code} eq $code, @{$self->{_des}};
    @r ? $r[0] : undef;
}

sub by_id {
    my ($self, $id) = @_;
    my @r = grep $_->{id} eq $id, @{$self->{_des}};
    @r ? $r[0] : undef;
}

sub default_extension {
    my ($self, $id) = @_;
    my $de = $self->by_id($id) or return 'txt';
    $de->{default_file_ext} || (split_exts($de))[0] || 'txt';
}

sub bitmap_by {
    my ($self, $getter, @codes) = @_;

    my @res = map 0, 1..$cats::de_req_bitfields_count;

    my $de_bitfield_num = 0;
    my $curr_de_bitfield = 0;

    use bigint; # Make sure 64-bit integers work on 32-bit platforms.

    for my $code (@codes) {
        my $de = $getter->($code) or die "$code not found in de list";
        $de_bitfield_num = int($de->{index} / $cats::de_req_bitfield_size);

        die 'too many de codes to fit in db' if $de_bitfield_num > $cats::de_req_bitfields_count - 1;

        $res[$de_bitfield_num] |= 1 << ($de->{index} % $cats::de_req_bitfield_size);
    }

    @res;
}

sub bitmap_by_ids {
    my $self = shift;
    my $id_to_de = { map { $_->{id} => $_ } @{$self->{_des}} };
    $self->bitmap_by(sub { $id_to_de->{$_[0]} }, @_);
}

sub bitmap_by_codes {
    my $self = shift;
    my $code_to_de = { map { $_->{code} => $_ } @{$self->{_des}} };
    $self->bitmap_by(sub { $code_to_de->{$_[0]} }, @_);
}

sub des { $_[0]->{_des} }

sub version { $_[0]->{_de_version} }

sub is_good_version {
    defined $_[1] && $_[1] == $_[0]->version;
}

sub check_supported {
    my ($given_des, $our_des) = @_;
    use bigint; # Make sure 64-bit integers work on 32-bit platforms.
    # 64-bit integers come from database as strings, ensure conversion.
    0 == grep $given_des->[$_] != ($given_des->[$_] & (0 + $our_des->[$_])), 0 .. $cats::de_req_bitfields_count - 1;
}

1;
