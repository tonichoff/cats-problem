use Test::Harness;

use lib '../CATS/Formal';
runtests(map "$_.t", qw(parser testset ../CATS/Formal/t/CATS-Formal));

1;
