use FindBin;
use Test::Harness;

runtests(map "$FindBin::Bin/$_.t", qw(parser source tag testset CATS-Formal));

1;
