package File::System::Real;

use strict;
use warnings;

our $VERSION = '1.01';

use Carp;
use File::Basename ();
use File::Copy ();
use File::Copy::Recursive;
use File::Path ();
use File::Spec;
use FileHandle;

use base 'File::System::Object';

=head1 NAME

File::System::Real - A file system module based on the real file system

=head1 SYNOPSIS

  use File::System;
  $root = File::System->new('Real', root => '/usr/local');

=head1 DESCRIPTION

This is the most basic file system implementation. It is purely implemented within terms of a real file system.

=head1 OPTIONS

This file system module accepts only a single object, C<root>. If not given, the current working directory is assumed for the value C<root>. All files returned by the file system will be rooted at the given (or assumed) point.

=cut

sub new {
	my $class = shift;
	my %args  = @_;

	$args{root} ||= '.';
	$args{root} = File::Spec->rel2abs($args{root});
	$args{root} = $class->canonify($args{root});
	my $root = File::Spec->canonpath($args{root});

	-e $root or croak "Sorry, root $root does not exist!";
	-d $root or croak "Sorry, root $root is not a directory!";

	return bless {
		fs_root  => $root,
		path     => '/',
		fullpath => $root,
	}, $class;
}

sub is_valid {
	my $self = shift;
	return -e $self->{fullpath};
}

sub root {
	my $self = shift;

	return bless {
		fs_root  => $self->{fs_root},
		path     => '/',
		fullpath => $self->{fs_root},
	}, ref $self;
}

sub exists {
	my $self = shift;
	my $path = shift;

	return -e $self->canonify_real($path);
}

sub lookup {
	my $self = shift;
	my $path = shift;

	my $abspath = $self->canonify($path);
	my $fullpath = $self->canonify_real($path);

	return undef
		unless -e $fullpath;

	return bless {
		fs_root  => $self->{fs_root},
		path     => $abspath,
		fullpath => $fullpath,
	}, ref $self;
}

sub glob {
	my $self = shift;
	my $glob = shift;

	my $absglob = $self->canonify($glob);

	my $fullglob = $self->canonify_real($absglob);

	return map {
		s/^$self->{fs_root}//;
		bless {
			fs_root  => $self->{fs_root},
			path     => $self->canonify($_),
			fullpath => $self->canonify_real($_),
		}, ref $self
	} glob($fullglob);
}

sub properties { 
	my $self = shift;

	return qw/
		basename
		dirname
		path
		dev
		ino
		mode
		nlink
		uid
		gid
		rdev
		size
		atime
		mtime
		ctime
		blksize
		blocks
	/;
}

sub settable_properties { 
	my $self = shift;

	return qw/
		mode
		uid
		gid
		atime
		mtime
	/;
}

sub _stat {
	my $self = shift;

	my @stat = stat $self->{fullpath};
	return \@stat;
}

sub get_property {
	my $self = shift;
	local $_ = shift;

	SWITCH: {
		/^basename$/ && do {
			return File::Basename::basename($self->{path});
		};
		/^dirname$/  && do {
			return File::Basename::dirname($self->{path});
		};
		/^path$/     && do {
			return $self->{path};
		};
		/^dev$/      && do {
			return $self->_stat->[0];
		};
		/^ino$/      && do {
			return $self->_stat->[1];
		};
		/^mode$/     && do {
			return $self->_stat->[2];
		};
		/^nlink$/    && do {
			return $self->_stat->[3];
		};
		/^uid$/      && do {
			return $self->_stat->[4];
		};
		/^gid$/      && do {
			return $self->_stat->[5];
		};
		/^rdev$/     && do {
			return $self->_stat->[6];
		};
		/^size$/     && do {
			return $self->_stat->[7];
		};
		/^atime$/    && do {
			return $self->_stat->[8];
		};
		/^mtime$/    && do {
			return $self->_stat->[9];
		};
		/^ctime$/    && do {
			return $self->_stat->[10];
		};
		/^blksize$/  && do {
			return $self->_stat->[11];
		};
		/^blocks$/   && do {
			return $self->_stat->[12];
		};
		DEFAULT: {
			return undef;
		}
	}
}

sub set_property {
	my $self  = shift;
	local $_  = shift;
	my $value = shift;

	SWITCH: {
		/^mode$/ && do {
			chmod $value, $self->{fullpath};
			last SWITCH;
		};
		/^uid$/ && do {
			chown $value, $self->get_property('gid'), $self->{fullpath};
			last SWITCH;
		};
		/^gid$/ && do {
			chown $self->get_property('uid'), $value, $self->{fullpath};
			last SWITCH;
		};
		/^atime$/ && do {
			utime $value, $self->get_property('mtime'), $self->{fullpath};
			last SWITCH;
		};
		/^mtime$/ && do {
			utime $self->get_property('atime'), $value, $self->{fullpath};
			last SWITCH;
		};
		DEFAULT: {
			croak "Cannot set unknown property '$_'";
		}
	}
}

sub rename {
	my $self = shift;
	my $name = shift;

	croak "The 'name' argument must be a plan name, not a path. However, the given value ($name) contains a slash."
		if $name =~ m#/#;

	my $abspath  = $self->canonify($self->dirname.'/'.$name);
	my $fullpath = $self->canonify_real($self->dirname.'/'.$name);

	rename $self->{fullpath}, $fullpath;

	$self->{path}     = $abspath;
	$self->{fullpath} = $fullpath;

	return $self;
}

sub move {
	my $self  = shift;
	my $to    = shift;
	my $force = shift || 0;

	UNIVERSAL::isa($to, ref $self)
		or croak "Move failed; the '$to' object is not a '",ref $self,"'";

	$to->{fs_root} eq $self->{fs_root}
		or croak "Move failed; the '$to' object belongs to a different root.";

	$to->is_valid
		or croak "Move failed; the '$to' object is not valid.";
	
	$to->is_container
		or croak "Move failed; the '$to' object is not a directory.";

	defined $to->child($self->basename)
		and croak "Move failed; the '$to/",$self->basename,"' object already exists.";	

	if ($self->is_container) {
		if ($force) {
			$to->mkdir($self->basename);
			File::Copy::Recursive::dircopy($self->{fullpath}, $to->{fullpath}.'/'.$self->basename)
				or croak "Move failed; dircopy failure to '$to'";
			File::Path::rmtree($self->{fullpath});
		} else {
			croak "Move failed; cannot move a directory unless the 'force' argument is true.";
		}
	} else {
		File::Copy::move($self->{fullpath}, $to->{fullpath});
	}

	my $name = $self->basename;

	$self->{path}     = $self->canonify($to->path.'/'.$name);
	$self->{fullpath} = $self->canonify_real($to->path.'/'.$name);

	return $self;
}

sub copy {
	my $self  = shift;
	my $to    = shift;
	my $force = shift || 0;

	ref $to eq ref $self
		or croak "The 'to' argument must refer to a '",ref $self,"' file system container.";

	$to->{fs_root} eq $self->{fs_root}
		or croak "The 'to' argument has a different file system root than that of this file, $self->{path}";
	
	$to->is_container
		or croak "The 'to' argument must be a directory, but '$to' is not.";

	defined $to->child($self->basename)
		and croak "Cannot copy $self to $to as $to/",$self->basename," already exists.";	

	if ($self->is_container) {
		if ($force) {
			$to->mkdir($self->basename);
			File::Copy::Recursive::dircopy($self->{fullpath}, $to->{fullpath}.'/'.$self->basename)
				or croak "Failed to move' $self->{fullpath}' to '$to->{fullpath}'";
		} else {
			croak "Cannot copy directory unless the 'force' argument is true.";
		}
	} else {
		File::Copy::copy($self->{fullpath}, $to->{fullpath});
	}

	return bless {
		fs_root  => $self->{fs_root},
		path     => $self->canonify($to->path.'/'.$self->basename),
		fullpath => $self->canonify_real($to->path.'/'.$self->basename),
	}, ref $self;
}

sub remove {
	my $self  = shift;
	my $force = shift;

	if (-d $self->{fullpath} && $force) {
		File::Path::rmtree($self->{fullpath});
	} elsif (-d $self->{fullpath} && $self->has_children) {
		croak "Cannot delete directory with children unless force is true.";
	} elsif (-d $self->{fullpath}) {
		rmdir $self->{fullpath};
	} else {
		unlink $self->{fullpath};
	}
}

sub has_content {
	my $self = shift;
	return -f $self->{fullpath};
}

sub is_container {
	my $self = shift;
	return -d $self->{fullpath};
}

sub is_readable {
	my $self = shift;
	return $self->has_content;
}

sub is_seekable {
	my $self = shift;
	# TODO This is naive. Seekability is a little less available than this
	# would indicate.
	return $self->has_content;
}

sub is_writable {
	my $self = shift;
	return $self->has_content;
}

sub is_appendable {
	my $self = shift;
	return $self->has_content;
}

sub open {
	my $self   = shift;
	my $access = shift;
	return FileHandle->new($self->{fullpath}, $access);
}

sub content {
	my $self = shift;

	my $fh = $self->open("r");
	my @lines = <$fh>;
	close $fh;

	return wantarray ? @lines : join '', @lines;
}

sub has_children {
	my $self = shift;

	opendir DH, $self->{fullpath};
	my @dirs = grep !/^\.\.?$/, readdir DH;
	closedir DH;

	return @dirs ? 1 : '';
}

sub children_paths {
	my $self = shift;
	
	opendir DH, $self->{fullpath};
	my @paths = map { s/^$self->{fs_root}//; $_ } readdir DH;
	closedir DH;

	return @paths;
}

sub children {
	my $self = shift;

	opendir DH, $self->{fullpath};
	my @children = map {
		if (/^\.\.?$/) {
			()
		} else {
			bless {
				fs_root  => $self->{fs_root},
				path     => $self->canonify($_),
				fullpath => $self->canonify_real($_),
			}, ref $self;
		}
	} readdir DH;
	closedir DH;

	return @children;
}

sub child {
	my $self = shift;
	my $name = shift;

	croak "Name given, '$name', is a path rather than a name (i.e., it contains a slash)." if $name =~ m#/#;

	my $abspath  = $self->canonify($name);
	my $fullpath = $self->canonify_real($name);

	if (-e $fullpath) {
		return bless {
			fs_root  => $self->{fs_root},
			path     => $abspath,
			fullpath => $fullpath,
		}, ref $self;
	} else {
		return undef;
	}
}

sub mkdir {
	my $self = shift;
	my $path = shift;

	my $abspath  = $self->canonify($path);
	my $fullpath = $self->canonify_real($path);

	File::Path::mkpath($fullpath, 0);

	-d $fullpath
		or croak "Failed to create directory '$abspath'";

	return bless {
		fs_root  => $self->{fs_root},
		path     => $abspath,
		fullpath => $fullpath,
	}, ref $self;
}

sub mkfile {
	my $self = shift;
	my $path = shift;

	my $fulldir = $self->canonify_real(File::Basename::dirname($path));

	File::Path::mkpath($fulldir, 0);

	my $abspath  = $self->canonify($path);
	my $fullpath = $self->canonify_real($path);

	my $fh = FileHandle->new(">$fullpath")
		or croak "Cannot create file $abspath: $!";
	close $fh;

	return bless {
		fs_root  => $self->{fs_root},
		path     => $abspath,
		fullpath => $fullpath,
	}, ref $self;
}

# =item $real_path = $obj->canonify_real($messy_path)
#
# Like C<canonify>, except that it returns a real absolute path.
#
# =cut

sub canonify_real {
	my $self = shift;
	my $path = shift;

	my $abspath  = $self->canonify($path);
	my $fullpath = File::Spec->canonpath(
	   File::Spec->catfile($self->{fs_root}, $abspath)
	);

	return $fullpath;
}

=head1 SEE ALSO

L<File::System>, L<File::System::Object>

=head1 AUTHOR

Andrew Sterling Hanenkamp, E<lt>hanenkamp@users.sourceforge.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2005 Andrew Sterling Hanenkamp. All Rights Reserved.

This software is distributed and licensed under the same terms as Perl itself.

=cut

1
