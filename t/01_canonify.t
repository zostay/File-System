use strict;
use warnings;

use File::Path;
use Test::More tests => 41;

BEGIN { use_ok('File::System') }

-d 't/root' && rmtree('t/root', 1);
mkpath('t/root/bar/baz', 1, 0700);

my $obj = File::System->new('Real', root => 't/root');

is($obj->canonify('//////'), '/');
is($obj->canonify('/foo/bar/baz/'), '/foo/bar/baz');
is($obj->canonify('/././././././././.'), '/');
is($obj->canonify('/../foo/../bar/baz/..'), '/bar');
is($obj->canonify('foo'), '/foo');
is($obj->canonify('/foo'), '/foo');
is($obj->canonify('../foo'), '/foo');
is($obj->canonify('foo/..'), '/');
is($obj->canonify('foo/bar/./..'), '/foo');
is($obj->canonify('/foo/bar/./..'), '/foo');

like($obj->canonify_real('//////'), qr(t/root$));
like($obj->canonify_real('/foo/bar/baz/'), qr(t/root/foo/bar/baz$));
like($obj->canonify_real('/././././././././.'), qr(t/root$));
like($obj->canonify_real('/../foo/../bar/baz/..'), qr(t/root/bar$));
like($obj->canonify_real('foo'), qr(t/root/foo$));
like($obj->canonify_real('/foo'), qr(t/root/foo$));
like($obj->canonify_real('../foo'), qr(t/root/foo$));
like($obj->canonify_real('foo/..'), qr(t/root$));
like($obj->canonify_real('foo/bar/./..'), qr(t/root/foo$));
like($obj->canonify_real('/foo/bar/./..'), qr(t/root/foo$));

$obj = $obj->lookup('bar/baz');
is($obj->canonify('//////'), '/');
is($obj->canonify('/foo/bar/baz/'), '/foo/bar/baz');
is($obj->canonify('/././././././././.'), '/');
is($obj->canonify('/../foo/../bar/baz/..'), '/bar');
is($obj->canonify('foo'), '/bar/baz/foo');
is($obj->canonify('/foo'), '/foo');
is($obj->canonify('../foo'), '/bar/foo');
is($obj->canonify('foo/..'), '/bar/baz');
is($obj->canonify('foo/bar/./..'), '/bar/baz/foo');
is($obj->canonify('/foo/bar/./..'), '/foo');

like($obj->canonify_real('//////'), qr(t/root$));
like($obj->canonify_real('/foo/bar/baz/'), qr(t/root/foo/bar/baz$));
like($obj->canonify_real('/././././././././.'), qr(t/root$));
like($obj->canonify_real('/../foo/../bar/baz/..'), qr(t/root/bar$));
like($obj->canonify_real('foo'), qr(t/root/bar/baz/foo$));
like($obj->canonify_real('/foo'), qr(t/root/foo$));
like($obj->canonify_real('../foo'), qr(t/root/bar/foo$));
like($obj->canonify_real('foo/..'), qr(t/root/bar/baz$));
like($obj->canonify_real('foo/bar/./..'), qr(t/root/bar/baz/foo$));
like($obj->canonify_real('/foo/bar/./..'), qr(t/root/foo$));

rmtree('t/root', 0);
