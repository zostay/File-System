use strict;
use warnings;

use File::Basename;
use File::Path;
use File::System::Test;
use Test::More tests => 308;

BEGIN { use_ok('File::System') }

-d 't/root' and rmtree('t/root', 1);
mkpath('t/root/bar', 1, 0700);

-d 't/root2' and rmtree('t/root2', 1);
mkpath('t/root2', 1, 0700);

my $root = File::System->new('Table', 
	'/'    => [ 'Real', root => 't/root' ],
	'/bar' => [ 'Real', root => 't/root2' ],
);

# Checking initial file system root
is_root_sane($root);

my @dirs = qw(
	.bar .bar/.baz .bar/.baz/.qux .file2
	bar bar/baz bar/baz/qux file2
);

my @files = qw(
	.baz .file1 .file2/bar .file2/foo .file3 .file4 .foo .qux
	baz file1 file2/bar file2/foo file3 file4 foo qux
);

for my $path (@dirs) {
	ok(defined $root->create($path, 'd'));
}

for my $path (@files) {
	ok(defined $root->create($path, 'f'));
}

for my $path (@dirs, @files) {
	ok($root->exists($path));
	is_object_sane($root->lookup($path));
}

# Check to make sure child does essentially the same
ok(defined $root->child('foo'));
ok(!defined $root->child('foo2'));

for my $path (@dirs, @files) {
 	my $obj = $root->lookup($path);

	is_object_sane($obj);
 
 	# properties
 	is_deeply([ $obj->properties ], [ qw/ basename dirname path object_type dev ino mode nlink uid gid rdev size atime mtime ctime blksize blocks / ]);
 	is_deeply([ $obj->settable_properties ], [ qw/ mode uid gid atime mtime / ]);
 
 	$obj->set_property('mode', 0700);
 	is($obj->get_property('mode') & 0777, 0700);
 
 	my $yesterday = time - 86400;
 	$obj->set_property('atime', $yesterday);
 	$obj->set_property('mtime', $yesterday);
 	is($obj->get_property('atime'), $yesterday);
 	is($obj->get_property('mtime'), $yesterday);
}

for my $path (@files) {
	if ($path =~ /^bar\/(.*)$/) {
		ok(-f "t/root2/$1");
	} else {
		ok(-f "t/root/$path");
	}

	my $obj = $root->lookup($path);

	is_content_sane($obj);
	is_content_writable($obj);
	
	my $dir;
	if ($obj->path =~ /^\/bar\//) {
		$dir = $root->create('bar/move_test', 'd');
	} else {
		$dir = $root->create('move_test', 'd');
	}

	is_content_mobile($obj, $dir);
	$dir->remove('force');
}

for my $path (@dirs) {
	if ($path =~ /^bar\/(.*)$/) {
		ok(-d "t/root2/$1");
	} else {
		ok(-d "t/root/$path");
	}
	
	my $obj = $root->lookup($path);

	is_container_sane($obj);

	next if $obj->path eq '/bar';

	my $dir;
	if ($obj->path =~ /^\/bar\//) {
		$dir = $root->create('bar/move_test', 'd');
	} else {
		$dir = $root->create('move_test', 'd');
	}

	is_container_mobile($obj, $dir);
	$dir->remove('force');
}

is_glob_and_find_consistent($root);

rmtree('t/root', 1);
rmtree('t/root2', 1);
