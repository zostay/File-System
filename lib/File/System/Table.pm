package File::System::Table;

use strict;
use warnings;

use base 'File::System::Object';

use Carp;
use File::System;

=head1 NAME

File::System::Table - A file system implementation for mounting other modules

=head1 SYNOPSIS

  use File::System;

  my $root = File::System->new('Table',
      '/'    => [ 'Real', root => '/home/foo' ],
      '/tmp' => [ 'Real', root => '/tmp' ],
      '/bin' => [ 'Real', root => '/bin' ],
  );

  my $file = $root->mkfile('/tmp/dude');
  my $fh = $file->open('w');
  print $fh "Party on! Excellent!\n";
  close $fh;

=head1 DESCRIPTION

This file system module allows for the creation of a tabular virtual file system. Each L<File::System::Table> is created with a root file system (at least) and then can have zero or more mounts to allow for more complicated file system handling. All mount points can be changed after the initial file system creation (except for the root, which is static).

=head2 MOUNT POINTS

There are a few rules regarding mount points that this system requires. This should be familiar to anyone familiar with Unix file system mounting:

=over

=item 1.

The root mount point (F</>) is special and static. It cannot be unmounted except by deleting the file system object altogether.

=item 2.

A specific mount point cannot be mounted more than once. I.e., the following code would fail:

  $root = File::System->new('Table', '/' => [ 'Real' ]);
  $root->mount('/tmp' => [ 'Real', root => '/tmp' ]);
  $root->mount('/tmp' => [ 'Real', root => '/var/tmp' ]); 
  # ^^^ ERROR! Mount point already in use!

=item 3.

A file system may only be mounted onto existing containers. When mounting a path, the path must exist as per the already present mount table and that path must represent a container. Otherwise, an error will occur. I.e., the following code would fail:

  $root = File::System->new('Table', '/' => [ 'Real' ]);
  $obj = $root->lookup('/foo');
  $obj->remove('force') if defined $obj;
  $root->mount('/foo' => [ 'Real', root => '/tmp' ]);
  # ^^^ ERROR! Mount point does not exist!

  $root->mkfile('/foo');
  $root->mount('/foo' => [ 'Real', root => '/tmp' ]);
  # ^^^ ERROR! Mount point is not a container!

=item 4.

Any content or containers within a container that is mounted to within the parent is immediately invisible. These objects are hidden by the child mount until the file system is unmounted.

=item 5.

A mount point cannot be set above an existing mount point so that it would hide an existing mount. I.e., the following code would fail:

  $root = File::System->new('Table', '/' => [ 'Real' ]);
  $obj = $root->mkdir('/foo/bar');
  $obj->mount('/foo/bar' => [ 'Real', root => '/tmp' ]);
  $obj->mount('/foo' => [ 'Real', root => '/var/tmp' ]);
  # ^^^ ERROR! Mount point hides an already mounted file system!

=item 6.

As a corollary to the fifth principle, a mount point cannot be removed above another mount point below. If you mount one file system within another, the inner file system must be unmounted prior to unmounting the outer.

=back

Because of these rules it is obvious that the order in which mounting takes place is significant and will affect the outcome. As such, the root mount must always be specified first in the constructor.

=head2 MOUNT TABLE API

This file system module provides a constructor (duh) and a few extra methods. All other methods are given in the documentation of L<File::System::Object>.

=over

=item $root = File::System-E<gt>new('Table', '/' =E<gt> $fs, ...)

The constructor establishes the initial mount table for the file system. The mount table must always contain at least one entry for the root directory (F</>). The root directory entry must always be the first entry given as well.

Each entry is made of two elements, the path to mount to and then a reference to either a reference to the file system object responsible for files under that mount point, or an array reference that can be passed to L<File::System> to create a file system object.

=cut

sub new {
	my $class = shift;

	$_[0] eq '/'
		or croak "The first mount point given must always be the root (/), but found '$_[0]' instead.";

	my $self = bless { cwd => '/' }, $class;

	while (($mp, $fs) = splice @_, 0, 2) {
		$self->mount($mp, $fs);
	}

	return $self;
}

=item $obj-E<gt>mount($path, $fs)

Each entry is made of two elements, the path to mount to and then a reference to either a reference to the file system object responsible for files under that mount point, or an array reference that can be passed to L<File::System> to create a file system object.

=cut

sub mount {
	my $self = shift;
	my $path = $self->canonify(shift);
	my $fs   = $self->_init_fs(shift);

	if ($path eq '/') {
		if (defined $self->{mounts}) {
			croak "The root mount point cannot be overridden.";
		} else {
			$self->{cwd_fs} = $self->{mounts}{$path} = $fs;
		}
	} else {
		my $dir = $self->lookup($path);

		defined $dir
			or croak "The mount point '$path' does not exist.";

		$dir->is_container
			or croak "The mount point '$path' is not a container.";

		my @inner = grep /^$path/, keys %{ $self->{mounts} };
		croak "The mount point '$inner[0]' must be unmounted before mount point '$path' may be used."
			if @inner;

		$dir->has_children
			and carp "Mounting on mount point '$path' will hide some files.";

		$self->{mounts}{$path} = $fs;
	}
}

=item $unmounted_fs = $fs-E<gt>unmount($path)

Unmounts the file system mounted to the given path. This method will raise an exception if the user attempts to unmount a path that has no file system mounted.

This method returns the file system that was mounted at the given path.

=cut

sub unmount {
	my $self = shift;
	my $path = $self->canonify($path);

	$path eq '/'
		and croak "The root mount point cannot be unmounted.";

	defined $self->{mounts}{$path}
		or croak "No file system is mounted at '$path'. Therefore it cannot be unmounted.";

	my @inner = grep /^$path./, keys %{ $self->{mounts} };
	croak "Mount point '$inner[0]' must be unmounted before '$path'"
		if @inner;

	delete $self->{mounts}{$path};
}

=item @paths = $fs-E<gt>mount_table

Returns the list of all paths that have been mounted to.

=cut

sub mount_table {
	my $self = shift;
	return keys %{ $self->{mounts} };
}

=back

=cut

sub _init_fs {
	my $self = shift;
	my $fs   = shift;

	if (UNIVERSAL::isa($fs, 'File::System::Object')) {
		return $fs;
	} elsif (ref $fs eq 'ARRAY') {
		return File::System->new(@$fs);
	} else {
		croak "File system must be an array reference or an actual File::System::Object. '$fs' is neither of these. See documentation of File::System::Table for details.";
	}
}

sub _resolve_fs {
	my $self = shift;
	my $path = $self->canonify(shift);

	# The mount point we want should be the longest one which matches our
	# given path name.
	my ($mp) = 
		sort { -(length($a) <=> length($b)) }
		grep { $path =~ /^$_/ }
		keys %{ $self->{mounts} };
	
	my $rel_path = substr $path, length($mp);
	$rel_path = '/'.$rel_path unless $rel_path =~ /^\//;

	return ($self->{mounts}{$mp}, $rel_path);
}

sub root {
	my $self = shift;

	return bless {
		cwd    => '/',
		cwd_fs => $self->{mounts}{'/'},
		mounts => $self->{mounts},
	}, ref $self;
}

sub exists {
	my $self = shift;
	my ($fs, $path) = $self->_resolve_fs(shift);
	return $fs->exists($path);
}

sub lookup {
	my $self        = shift;
	my $cwd         = $self->canonify($_[0]);
	my ($fs, $path) = $self->_resolve_fs(shift);

	return bless {
		cwd    => $cwd,
		cwd_fs => $fs->lookup($path),
		mounts => $self->{mounts},
	}, ref $self;
}

#sub glob {
#	# TODO Deep thoughts. How do I do this?
#}
#
#sub find {
#	# TODO Deep thoughts. How do I do this?
#}

sub _delegate_fs {
	my $self     = shift;
	my @caller   = caller 0;
	my ($method) = $caller[3] =~ /(\w+)$/;

	no strict 'refs';
	return $self->{cwd_fs}->$method->(@_);
}

*is_valid            = \&_delegate_fs;
*properties          = \&_delegate_fs;
*settable_properties = \&_delegate_fs;
*get_property        = \&_delegate_fs;
*set_property        = \&_delegate_fs;
*remove              = \&_delegate_fs;
*has_content         = \&_delegate_fs;
*is_container        = \&_delegate_fs;
*is_readable         = \&_delegate_fs;
*is_seekable         = \&_delegate_fs;
*is_writable         = \&_delegate_fs;
*is_appendable       = \&_delegate_fs;
*open                = \&_delegate_fs;
*content             = \&_delegate_fs;
*has_children        = \&_delegate_fs;
*children_paths      = \&_delegate_fs;
*children            = \&_delegate_fs;
*child               = \&_delegate_fs;
*mkdir               = \&_delegate_fs;
*mkfile              = \&_delegate_fs;

sub rename {
	my $self = shift;
	my $name = shift;

	$self->{cwd_fs}->rename($name);
	
	$self->{cwd} =~ s#[^/]+$ #$name#x;
}

sub move {
	my $self  = shift;
	my $path  = shift;
	my $force = shift;

	$self->{cwd_fs}->move($path, $force);

	substr $self->{cwd}, 0, length($self->basename), $path;
}

sub copy {
	my $self  = shift;
	my $path  = shift;
	my $force = shift;

	my $copy = $self->{cwd_fs}->move($path, $force);
	my $copy_cwd = $self->{cwd};
	substr $copy_cwd, 0, length($self->basename), $path;

	return bless {
		cwd_fs => $copy,
		cwd    => $copy_cwd,
		mounts => $self->{mounts},
	}, ref $self;
}

=head1 BUGS

The C<copy> and C<move> methods will fail if used between file systems. This can be remedied, but it will require some delicate planning that hasn't yet been done.

The C<glob> and C<find> methods rely upon the slowish defaults. This situation could probably be improved with a little bit of effort.

=head1 SEE ALSO

L<File::System>, L<File::System::Object>, L<File::System::Real>

=head1 AUTHOR

Andrew Sterling Hanenkamp, E<lt>hanenkamp@users.sourceforge.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2005 Andrew Sterling Hanenkamp. All Rights Reserved.

This library is distributed and licensed under the same terms as Perl itself.

=cut

1
