use Test::Harness;

runtests(map "$_.t", qw(parser testset));

1;
