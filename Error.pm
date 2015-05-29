package CATS::Formal::Error;


my $error;

sub set {
    $error = $_[0];
    die $error;
}

sub clear {
    $error = undef;
}

sub get {
    return $error;
}

1;