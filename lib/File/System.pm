package File::System;

use strict;
use warnings;

our $VERSION = '1.01';

# declaring avoids 'Name "File::System::prune" used only once: possible typo'
our $prune;

=head1 NAME

File::System - Central factory for File::System modules

=head1 SYNOPSIS

  my $root = File::System->new("Real", root => '/var/chroot/foo');

  my $file = $root->lookup('/etc/fstab');
  print $file->lines;

=head1 DESCRIPTION

B<Nota Bene:> This package is still in development, so some aspects of the API are likely to change.

The L<File::System> library is intended to provide an interface to a file system. Generally, a file system is a heirarchical arrangement of records commonly found on most modern computers. This library attempts to generalize this idea as it pertains to loading and accessing these files. This is not meant to generalize on the specifics of file system implementations or get into hardware details. 

The goal of this system is not to present the file system in a native way, but to provide the Perl program using it a simple hook into a potentially complex structure. Thus, certain file system module requirements may force unnatural or arbitrary constraints on the file system appearance. The most notable is that this implementation purposely does not address the concept of "volumes" except to state that such things should just be made parts of the file system under an artificial root.

This system is also still immature and certain aspects---notably the concept of "capabilities" and "permissions"---are absent. These may be added in future making existing file modules created to this system incompatible with future revisions. I will try to make sure that such things are "optional" such that the system can function in a crippled way without support for these future additions when they come, but I make guarantees.

=head2 FACTORY SYSTEM

The C<File::System> module provides a central interface into loading other C<File::System> modules. It provides a single method for instantiating a file system module:

=over 

=item $root = File::System->new($module_name, ...)

This will create and return the root file system object (i.e., an instance of L<File::System::Object>) for the file system module named C<$module_name>. 

If the C<$module_name> does not contain any colons, then it the package "C<File::System::$module_name>" is loaded and the C<new> method for that package is used to create the object. Otherwise, the C<$module_name> is loaded and it's C<new> method is used. For example,

  $fs = File::System->new('Real')
  # Module File::System::Real is loaded
  # Method File::System::Real->new is called
  
  $fs = File::System->new('My::File::System::Foo')
  # Module My::File::System::Foo is loaded
  # Method My::File::System::Foo->new is called

Any additional arguments passed to this method are then passed to the C<new> method of the loaded package.

=cut

sub new {
	my $class = shift;
	my $fs    = shift;

	$fs =~ /[\w:]+/
		or die "The given FS package, $fs, doesn't appear to be a package name.";

	$fs =~ /:/
		or $fs = "File::System::$fs";

	eval "use $fs";
	warn "Failed to load FS package, $fs: $@" if $@;

	return $fs->new(@_);
}

=back

The returned object will behave according to the documentation available in L<File::System::Object>.

=head1 TODO

I would like to create a set of regular regression tests that can be applied to any module to prove its working order.

=head1 SEE ALSO

L<File::Find>, L<File::System::Object>

=head1 AUTHOR

Andrew Sterling Hanenkamp, E<lt>hanenkamp@users.sourceforge.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2005 Andrew Sterling Hanenkamp. All Rights Reserved.

This software is distributed and licensed under the same terms as Perl itself.

=cut

1
