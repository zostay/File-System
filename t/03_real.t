use strict;
use warnings;

use File::Basename;
use File::Path;
use Test::More tests => 1177;

BEGIN { use_ok('File::System') }

-d 't/root' and rmtree('t/root', 1);
mkpath('t/root', 1, 0700);

my $root = File::System->new('Real', root => 't/root');

# Checking initial file system root
ok(defined $root);

my %paths = (
	''               => { path => '/', parent => '/' },
	'/'              => { path => '/', parent => '/' },
	'.'              => { path => '/', parent => '/' },
	'..'             => { path => '/', parent => '/' },
	'.bar'           => { path => '/.bar', parent => '/' },
	'.bar/.baz'      => { path => '/.bar/.baz', parent => '/.bar' },
	'.bar/.baz/.qux' => { path => '/.bar/.baz/.qux', parent => '/.bar/.baz' },
	'.baz'           => { path => '/.baz', parent => '/', file => 1 },
	'.file1'         => { path => '/.file1', parent => '/', file => 1 },
	'.file2'         => { path => '/.file2', parent => '/' },
	'.file2/bar'     => { path => '/.file2/bar', parent => '/.file2', file => 1 },
	'.file2/foo'     => { path => '/.file2/foo', parent => '/.file2', file => 1 },
	'.file3'         => { path => '/.file3', parent => '/', file => 1 },
	'.file4'         => { path => '/.file4', parent => '/', file => 1 },
	'.foo'           => { path => '/.foo', parent => '/', file => 1 },
	'.qux'           => { path => '/.qux', parent => '/', file => 1 },
	'bar'            => { path => '/bar', parent => '/' },
	'bar/baz'        => { path => '/bar/baz', parent => '/bar' },
	'bar/baz/qux'    => { path => '/bar/baz/qux', parent => '/bar/baz' },
	'baz'            => { path => '/baz', parent => '/', file => 1 },
	'file1'          => { path => '/file1', parent => '/', file => 1 },
	'file2'          => { path => '/file2', parent => '/' },
	'file2/bar'      => { path => '/file2/bar', parent => '/file2', file => 1 },
	'file2/foo'      => { path => '/file2/foo', parent => '/file2', file => 1 },
	'file3'          => { path => '/file3', parent => '/', file => 1 },
	'file4'          => { path => '/file4', parent => '/', file => 1 },
	'foo'            => { path => '/foo', parent => '/', file => 1 },
	'qux'            => { path => '/qux', parent => '/', file => 1 },
);

# mkdir/mkfile
for my $path (keys %paths) {
	if ($paths{$path}{file}) {
		ok(defined $root->mkfile($path));
	} else {
		ok(defined $root->mkdir($path));
	}
}

# Make sure root is the same as new root
is($root->path, $root->root->path);

# Make sure exists detects existing files and doesn't detect non-existant files
ok($root->exists(''));
ok($root->exists('/'));
ok($root->exists('.'));
ok($root->exists('..'));
ok($root->exists('bar'));
ok($root->exists('/foo'));
ok(!$root->exists('quux'));
ok(!$root->exists('/quux'));
ok(!$root->exists('/quux/foo/bar/baz'));
ok($root->exists('bar/baz/qux'));
ok($root->exists('/bar/baz/qux'));

# Check to make sure child does essentially the same
ok(defined $root->child('foo'));
ok(!defined $root->child('foo2'));

for my $path (sort keys %paths) {
	my $obj = $root->lookup($path);

	# lookup
	ok(defined $obj);
	is($obj->path, $paths{$path}{path});

	# stringify
	is("$obj", $paths{$path}{path});

	# eq
	ok($obj eq $paths{$path}{path});

	# basename
	is($obj->basename, basename($paths{$path}{path}));

	# dirname
	is($obj->dirname, dirname($paths{$path}{path}));

	# is_root
	is($obj->is_root, $paths{$path}{path} eq '/');

	# parent
	is($obj->parent->path, $paths{$path}{parent});

	# properties
	is_deeply([ $obj->properties ], [ qw/ basename dirname path dev ino mode nlink uid gid rdev size atime mtime ctime blksize blocks / ]);
	is_deeply([ $obj->settable_properties ], [ qw/ mode uid gid atime mtime / ]);

	$obj->set_property('mode', 0700);
	is($obj->get_property('mode') & 0777, 0700);

	my $yesterday = time - 86400;
	$obj->set_property('atime', $yesterday);
	$obj->set_property('mtime', $yesterday);
	is($obj->get_property('atime'), $yesterday);
	is($obj->get_property('mtime'), $yesterday);

	# has_content
	is($obj->has_content, -f "t/root/$paths{$path}{path}");

	# is_container
	is($obj->is_container, -d "t/root/$paths{$path}{path}");

	if ($obj->has_content) {
		# rename
		my $name = $obj->basename;
		my $renamed_path = $paths{$path}{path};
		$renamed_path =~ s{$name$}{tofu};
		
		is($obj->rename('tofu')->path, $renamed_path);
		ok(!-f "t/root/$paths{$path}{path}");
		ok(-f "t/root/$renamed_path");
		is($obj->rename($name)->path, $paths{$path}{path});
		ok(-f "t/root/$paths{$path}{path}");
		ok(!-f "t/root/$renamed_path");

		# Prepare for move/copy
		my $dir = $root->mkdir('tofu');
		my $orig_dir = $obj->dirname;

		# move
		is($obj->move($dir)->path, "/tofu/".$obj->basename);
		ok(!-f "t/root/$paths{$path}{path}");
		ok(-f "t/root/tofu/".$obj->basename);
		is($obj->move($obj->lookup($orig_dir))->path, $paths{$path}{path});
		ok(-f "t/root/$paths{$path}{path}");
		ok(!-f "t/root/tofu/".$obj->basename);

		# copy
		my $copy;
		is(($copy = $obj->copy($dir))->path, "/tofu/".$obj->basename);
		ok(-f "t/root/$paths{$path}{path}");
		ok(-f "t/root/tofu/".$obj->basename);

		# remove
		$copy->remove;
		ok(!-f "t/root/tofu/".$obj->basename);
		$dir->remove('force');

		# Content is_*
		ok($obj->is_readable);
		ok($obj->is_writable);
		ok($obj->is_seekable);
		ok($obj->is_appendable);

		# open
		ok(my $fh = $obj->open("w"));
		print $fh "Hello World\n";
		print $fh "foo\n";
		print $fh "bar\n";
		print $fh "baz\n";
		print $fh "qux\n";
		close $fh;

		# content
		my $content = $obj->content;
		is($content, "Hello World\nfoo\nbar\nbaz\nqux\n");
		my @content = $obj->content;
		is_deeply(\@content, [ "Hello World\n", "foo\n", "bar\n", "baz\n", "qux\n" ]);
	}

	if ($obj->is_container) {
		my @children = 
			grep { m[^$paths{$path}{path}.] }
			map  { $paths{$_}{path} }
			keys %paths;

		unless ($obj->is_root) {
			# rename
			my $name = $obj->basename;
			my $renamed_path = $paths{$path}{path};
			$renamed_path =~ s{$name$}{tofu};

			my @renamed_children =
				map { 
					my $o = $_; 
					substr $o, 0, length($paths{$path}{path}), $renamed_path;
			   		$o
				} @children;

			is($obj->rename('tofu')->path, $renamed_path);
			ok(!-e "t/root/$paths{$path}{path}");
			for my $child_path (@children) {
				ok(!-e "t/root/$child_path");
			}
			ok(-e "t/root/$renamed_path");
			for my $child_path (@renamed_children) {
				ok(-e "t/root/$child_path");
			}
			is($obj->rename($name)->path, $paths{$path}{path});
			ok(-e "t/root/$paths{$path}{path}");
			for my $child_path (@children) {
				ok(-e "t/root/$child_path");
			}
			ok(!-e "t/root/$renamed_path");
			for my $child_path (@renamed_children) {
				ok(!-e "t/root/$child_path");
			}
		
			# prepare for move/copy	
			my $dir = $root->mkdir('tofu');
			my $orig_dir = $obj->dirname;
			
			my $new_path = "/tofu/".$obj->basename;

			my @new_children =
				map { 
					my $o = $_; 
					substr $o, 0, length($paths{$path}{path}), $new_path;
			   		$o
				} @children;

			# move
			is($obj->move($dir, 'force')->path, $new_path);
			ok(!-e "t/root/$paths{$path}{path}");
			for my $child_path (@children) {
				ok(!-e "t/root/$child_path");
			}
			ok(-e "t/root/$new_path");
			for my $child_path (@new_children) {
				ok(-e "t/root/$child_path");
			}
			is($obj->move($obj->lookup($orig_dir), 'force')->path, $paths{$path}{path});
			ok(-e "t/root/$paths{$path}{path}");
			for my $child_path (@children) {
				ok(-e "t/root/$child_path");
			}
			ok(!-e "t/root/$new_path");
			for my $child_path (@new_children) {
				ok(!-e "t/root/$child_path");
			}

			# copy
			my $copy;
			is(($copy = $obj->copy($dir, 'force'))->path, $new_path);
			ok(-e "t/root/$paths{$path}{path}");
			for my $child_path (@children) {
				ok(-e "t/root/$child_path");
			}
			ok(-e "t/root/$new_path");
			for my $child_path (@new_children) {
				ok(-e "t/root/$child_path");
			}

			# remove
			$copy->remove('force');
			for my $child_path (@children) {
				ok(!-e "t/root/tofu/$child_path");
			}
			$dir->remove('force');
		}

		# has_children
		if (@children) {
			ok($obj->has_children);
		} else {
			ok(!$obj->has_children);
		}

		# children_paths
		is_deeply(
			[ sort($obj->children_paths) ], 
			[ sort('.', '..', 
				map { m[^$paths{$path}{path}/?([^/]+)] } 
				grep !m[^$paths{$path}{path}/?[^/]+/], @children) ]
		);

		# children
		is_deeply(
			[ sort($obj->children) ], 
			[ sort( 
				map { $root->lookup($_) } 
				grep !m[^$paths{$path}{path}/?[^/]+/], @children) ]
		);

		for (@children) {
			next if m[^$paths{$path}{path}/?[^/]+/];
			my ($name) = m[^$paths{$path}{path}/?([^/]+)];

			is_deeply($obj->child($name), $root->lookup($_));
		}
	}
}

# globbing
is_deeply([ $root->glob('*{ar,az}') ], [ map { $root->lookup($_) } qw( /bar /baz ) ]);
is_deeply([ $root->glob('*') ], [ map { $root->lookup($_) } qw( /bar /baz /file1 /file2 /file3 /file4 /foo /qux ) ]);
is_deeply([ $root->glob('.*') ], [ map { $root->lookup($_) } qw( / / /.bar /.baz /.file1 /.file2 /.file3 /.file4 /.foo /.qux ) ]);
is_deeply([ $root->glob('*/*') ], [ map { $root->lookup($_) } qw( /bar/baz /file2/bar /file2/foo ) ]);
is_deeply([ $root->glob('/*/*') ], [ map { $root->lookup($_) } qw( /bar/baz /file2/bar /file2/foo ) ]);

# find
sub files_not_starting_with_dot {
	my $file = shift;
	return $file->basename !~ /^\./;
}

sub files_not_starting_with_dot_pruned {
	my $file = shift;
	return 1 if $file->path eq '/';
	$File::System::prune = 1 if $file->basename !~ /\./;
	return 1;
}

is_deeply([ $root->find(\&files_not_starting_with_dot) ], [ map { $root->lookup($_) } qw( / /.file2/bar /.file2/foo /bar /bar/baz /bar/baz/qux /baz /file1 /file2 /file2/bar /file2/foo /file3 /file4 /foo /qux ) ]);
is_deeply([ $root->find(\&files_not_starting_with_dot_pruned) ], [ map { $root->lookup($_) } qw( / /.bar /.bar/.baz /.bar/.baz/.qux /.baz /.file1 /.file2 /.file2/bar /.file2/foo /.file3 /.file4 /.foo /.qux /bar /baz /file1 /file2 /file3 /file4 /foo /qux ) ]);

rmtree('t/root', 1);
