use FindBin;
use Test::Harness;

runtests(map "$FindBin::Bin/$_.t", qw(parser testset ../CATS/Formal/t/CATS-Formal));

1;
