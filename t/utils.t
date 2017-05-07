use strict;
use warnings;

use FindBin;
use Test::More tests => 9;
use Test::Exception;

use lib '..';
use lib $FindBin::Bin;

use CATS::Utils qw(group_digits);

is group_digits(''), '', 'group_digits empty';
is group_digits(1), '1', 'group_digits 1';
is group_digits(12), '12', 'group_digits 12';
is group_digits(123), '123', 'group_digits 123';
is group_digits(1234), '1 234', 'group_digits 1234';
is group_digits(12345), '12 345', 'group_digits 1234';
is group_digits(1234567890), '1 234 567 890', 'group_digits 1234567890';
is group_digits(10 ** 8), '100 000 000', 'group_digits 10^8';
is group_digits(234567890, '_'), '234_567_890', 'group_digits sep 234567890';

