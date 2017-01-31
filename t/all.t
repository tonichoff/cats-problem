use FindBin;
use Test::Harness;

use lib "$FindBin::Bin/../CATS/Formal";
runtests(map "$FindBin::Bin/$_.t", qw(parser tag testset ../CATS/Formal/t/CATS-Formal));

1;
