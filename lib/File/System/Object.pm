package File::System::Object;

use strict;
use warnings;

our $VERSION = '1.01';

use Parse::RecDescent;

=head1 NAME

File::System::Object - Abstract class that every file system module builds upon

=head1 DESCRIPTION

Before reading this documentation, you should see L<File::System>.

File system modules extend this class to provide their functionality. A file system object represents a path in the file system and provides methods to locate other file system objects either relative to this object or from an absolute root.

Throughout this documentation, there are additional notes for module authors. If you are not a module author (i.e., "I just want to use this thing!"), you may ignore these notes.

=head2 FEATURES

The basic idea is that every file system is comprised of objects. In general, all file systems will contain files and directories. Files are object which contain binary or textual data, while directories merely contain more files. Because any given file system might have arbitrarily many (or few) different types and the types might not always fall into the "file" or "directory" categories, the C<File::System::Object> attempts to generalize this functionality into "content" and "container". 

More advanced types might also be possible, e.g. symbolic links, devices, FIFOs, etc. However, at this time, no general solution is provided for handling these. (Individual file system modules may choose to add support for these in whatever way seems appropriate.)

Each file system object must specify a method stating whether it contains file content and another method stating whether it may contain child files. It is possible that a given file system implementation provides both simultaneously in a single object.

All file system objects allow for the lookup of other file system object by relative or absolute path names.

=head2 LOOKUP METHODS

These methods provide the most generalized functionality provided by all objects. Each path specified to each of these must follow the rules given by the L</"FILE SYSTEM PATHS"> section and may either be relative or absolute. If absolute, the operation performed will be based around the file system root. If relative, the operation performed depends on whether the object is a container or not. If a container, paths are considered relative to I<this> object. If not a container, paths are considered relative to the I<parent> of the current object.

=over

=item $root = $obj-E<gt>root

Return an object for the root file system.

B<Module Authors:> You must implement this object.

=item $test = $obj-E<gt>exists($path)

Check the given path C<$path> and determine whether a file system object exists at that path. Return a true value if there is such an object or false otherwise.

B<Module Authors:> A default (albeit I<very slow>) implementation is provided of this method.

=cut

sub exists {
	my $self = shift;
	my $path = shift;

	return defined $self->lookup($path);
}

=item $file = $obj-E<gt>lookup($path)

Lookup the given path C<$path> and return a L<File::System::Object> reference for that path or C<undef>.

B<Module Authors:> A default (albeit I<very slow>) implementation is provided of this method.

=cut

sub lookup {
	my $self = shift;
	my $path = shift;

	my $abspath = $self->canonify($path);

	if ($self->is_root) {
		my $result = $self;
		my @components = split m#/#, $path;
		for my $component (@components) {
			$self->is_container && ($result = $result->child($component))
				or return undef;
		}

		return $result;
	} else {
		return $self->root->lookup($abspath);
	}
}

=item @objs = $obj->glob($glob)

Find all files matching the given file globs C<$glob>. The glob should be a typical csh-style file glob---see L</"FILE SYSTEM PATHS"> below. Returns all matching objects.

B<Module Authors:> A generic and slow implementation is provided.

=cut

sub glob {
	my $self = shift;
	my $glob = shift;

	my @components = split /\//, $glob;

	my @in = $self->children;
	my @out;

	for my $component (@components) {
		return () unless @in;

		@out = $self->match_glob($component, @in);
		@in = map { $self->is_container ? $self->children : () } @out;
	}

	return @out;
}

=item @files = $obj->find($want, @paths)

This is similar in function to, but very different in implementation from L<File::Find>.

Find all files matching or within the given paths C<@paths> or any subdirectory of those paths, which pass the criteria specifed by the C<$want> subroutine.  If no C<@paths> are given, then "C<$obj>" is considered to be the path to search within.

The C<$want> subroutine will be called once for every file found under the give paths. The C<$want> subroutine may expect a single argument, the L<File::System::Object> representing the given file. The C<$want> subroutine should return true to add the file to the returned list or false to leave the file out. The C<$want> subroutine may also set the value of C<$File::System::prune> to a true value in order to cause all contained child object to be skipped from search.

The implementation should perform a depth first search so that children are checked immediately after their parent (unless the children are pruned, of course).

B<Module Authors:> A default implementation of this method has been provided.

=cut

sub find {
	my $self = shift;
	my $want = shift;

	my @dirs = @_ || ($self);

	my @open = map { $_ = $self->lookup($_) unless ref $_; $_ } @dirs;

	local $File::System::prune;

	my @found;
	while (my $file = shift @open) {
		$File::System::prune = 0;
		push @found, $file if $want->($file);

		unshift @open, $file->children
			if !$File::System::prune && $file->is_container;
	}

	return @found;
}

=back

=head2 METADATA METHODS

These are the general methods that every L<File::System::Object> will provide.

=over

=item "$obj"

The stringify operator is overloaded so that if this value is treated as a string it will take on the value of the "C<path>" property.

=cut

use overload 
	'""'  => sub { shift->path },
	'eq'  => sub { shift->path eq shift },
	'ne'  => sub { shift->path ne shift },
	'cmp' => sub { shift->path cmp shift };

=item $name = $obj-E<gt>is_valid

This method returns whether or not the object is still valid (i.e., the object it refers to still exists).

B<Module Authors:> An implementation of this method must be provided.

=item $name = $obj-E<gt>basename

This is the base name of the object (local name with the rest of the path stripped out). This value is also available as C<$obj-E<gt>get_property('basename')>

B<Module Authors:> An implementation of this method is provided.

=cut

sub basename {
	my $self = shift;
	return $self->get_property('basename');
}

=item $path = $obj-E<gt>dirname

This the absolute canonical path up to but not including the base name. If the object represents the root path of the file system (i.e., F<..> = F<.>), then it is possible that C<basename> = C<dirname> = C<path>. This value is also available as C<$obj-E<gt>get_property('dirname')>.

B<Module Authors:> An implementation of this method is provided.

=cut

sub dirname {
	my $self = shift;
	return $self->get_property('dirname');
}

=item $path = $obj-E<gt>path

This is the absolute canonical path to the object. This value is also available as C<$obj-E<gt>get_property('path')>.

B<Module Authors:> An implementation of this method is provided.

=cut

sub path {
	my $self = shift;
	return $self->get_property('path');
}

=item $test = $obj-E<gt>is_root

Returns true if this file system object represents the file system root.

B<Module Authors:> A default implementation is provided.

=cut

sub is_root {
	my $self = shift;
	return $self->path eq '/';
}

=item $parent_obj = $obj-E<gt>parent

This is equivalent to:

  $parent_obj = $obj->lookup($obj->dirname);

of you can think of it as:

  $parent_obj = $obj->lookup('..');

This will return the file system object for the container. It will return itself if this is the root container.

B<Module Authors:> A default implementation of this method is provided.

=cut

sub parent {
	my $self = shift;
	return $self->lookup($self->dirname);
}

=item @keys = $obj-E<gt>properties

Files may have an arbitrary set of properties associated with them. This method merely returns all the possible keys into the C<get_property> method.

B<Module Authors:> A definition for this method must be given.

=item @keys = $obj-E<gt>settable_properties

The keys returned by this method should be a subset of the keys returned by C<properties>. These are the modules upon which it is legal to call the C<set_property> method.

B<Module Authors:> A definition for this method must be given.

=item $value = $obj-E<gt>get_property($key)

Files may have an arbitrary set of properties associated with them. Many of the common accessors are just shortcuts to calling this method.

B<Module Authors:> A definition for this method must be given.

=item $obj-E<gt>set_property($key, $value)

This sets the property given by C<$key> to the value in C<$value>. This should fail if the given key is not found in C<$key>.

=item $obj-E<gt>rename($name)

Renames the name of the file to the new name. This method cannot be used to move the file to a different location. See C<move> for that.

B<Module Authors:> A definition for this method must be given.

=item $obj-E<gt>move($to, $force)

Moves the file to the given path. After running, this object should refer to the file in it's new location. The C<$to> argument must be a reference to the file system container (from the same file system!) to move this object into.  This method must fail if C<$obj> is a container and C<$force> isn't given or is false.

If you move a container using the C<$force> option, and you have references to files held within that container, all of those references are probably now invalid.

B<Module Authors:> A definition for this method must be given.

=item $copy = $obj-E<gt>copy($to, $force)

Copies the file to the given path. This object should refer to the original. The object representing the copy is returned. The c<$to> argument must refer to a reference to a file system container (from the same file system!). This method must fail if C<$obj> is a container and C<$force> isn't given or is false.

B<Module Authors:> A definition for this method must be given.

=item $obj-E<gt>remove($force)

Deletes the object from the file system entirely. In general, this means that the object is now completely invalid. 

The C<$force> option, when set to a true value, will remove containers and all their children and children of children, etc.

B<Module Authors:> A definition for this method must be given.

=item $test = $obj-E<gt>has_content

Returns a true value if the object contains file content. See L</"CONTENT METHODS"> for additional methods.

B<Module Authors:> A definition for this method must be given.

=item $test = $obj-E<gt>is_container

Returns a true value if the object may container other objects. See L</"CONTAINER METHODS"> for additional methods.

B<Module Authors:> A definition for this method must be given.

=back

=head2 CONTENT METHODS

These methods are provided if C<has_content> returns a true value.

=over

=item $test = $obj-E<gt>is_readable

This returns a true value if the file data can be read from---this doesn't refer to file permissions, but to actual capabilities. Can someone read the file? This literally means, "Can the file be read as a stream?"

B<Module Authors:> A definition for this method must be given if C<has_content> may return true.

=item $test = $obj-E<gt>is_seekable

This returns a true value if the file data is available for random-access. This literally means, "Are the individual bytes of the file addressable?"

B<Module Authors:> A definition for this method must be given if C<has_content> may return true.

=item $test = $obj-E<gt>is_writable

This returns a true value if the file data can be written to---this doesn't refer to file permissions, but to actual capabilities. Can someone write to the file? This literally means, "Can the file be overwritten?"

I<TODO Can this be inferred from C<is_seekable> and C<is_appendable>?>

B<Module Authors:> A definition for this method must be given if C<has_content> may return true.

=item $test = $obj-E<gt>is_appendable

This returns a true value if the file data be appended to. This literally means, "Can the file be written to as a stream?" 

B<Module Authors:> A definition for this method must be given if C<has_content> may return true.

=item $fh = $obj-E<gt>open($access)

Using the same permissions, C<$access>, as L<FileHandle>, this method returns a file handle or a false value on failure.

B<Module Authors:> A definition for this method must be given if C<has_content> may return true.

=item $content = $obj-E<gt>content

=item @lines = $obj-E<gt>content

In scalar context, this method returns the whole file in a single scalar. In list context, this method returns the whole file as an array of lines (with the newline terminator defined for the current system left intact).

B<Module Authors:> A definition for this method must be given if C<has_content> may return true.

=back

=head2 CONTAINER METHODS

These methods are provided if C<is_container> returns a true value.

=over

=item $test = $obj-E<gt>has_children

Returns true if this container has any child objects (i.e., any child objects in addition to the mandatory '.' and '..').

B<Module Authors:> A definition for this method must be given if C<is_container> may return true.

=item @paths = $obj-E<gt>children_paths

Returns the relative paths of all children of the given container. The first two paths should always be '.' and '..', respectively. These two paths should be present within anything that returns true for C<is_container>.

B<Module Authors:> A definition for this method must be given if C<is_container> may return true.

=item @children = $obj-E<gt>children

Returns the child C<File::System::Object>s for all the actual children of this container. This is approxmiately the same as:

  @children = map { $vfs->lookup($_) } grep !/^\.\.?$/, $obj->children_paths;

Notice that the objects for '.' and '..' are I<not> returned.

B<Module Authors:> A definition for this method must be given if C<is_container> may return true.

=item $child = $obj-E<gt>child($name)

Returns the child C<File::System::Object> that matches the given C<$name> or C<undef>.

B<Module Authors:> A definition for this method must be given if C<is_container> may return true.

=item $child = $obj-E<gt>mkdir($path)

Creates a container at the the given path C<$path> relative to the current object C<$obj>. Returns the newly created child. If the given path C<$path> requires more than one container be created (i.e., one or more of the parents of the ultimate container doesn't exist), then the file object should create all the parent objects necessary as well. Only the ultimate container will be returned.

B<Module Authors:> A definition for this method must be given if C<is_container> may return true.

=item $child = $obj-E<gt>mkfile($path)

Creates a content file at the given path C<$path> relative to the current object C<$obj>. Returns the newly created child. If the given path C<$path> requires that parent containers of the content file be created (i.e., one or more of the parents of the ultimate file doesn't exist), then the object should create all the parent objects necessary as well. Only the ultimate content object will be returned.

B<Module Authors:> A definition for this method must be given if C<is_container> may return true.

=back

=head1 FILE SYSTEM PATHS

Paths are noted as follows:

=over

=item "/"

The "/" alone represents the ultimate root of the file system.

=item "filename"

File names may contain any character except the forward slash. 

The underlying file system may not be able to cope with all characters. As such, it is legal for a file system module to throw an exception if it is not able to cope with a given file name.

Files can never have the name "." or ".." because of their special usage (see below). 

=item "filename1/filename2"

The slash is used to indicate that "filename2" is contained within "filename1". In general, the file system module doesn't really cope with "relative" file names, as might be indicated here. However, the L<File::System::Object> does provide this functionality in a way.

=item "."

The single period indicates the current file. It is legal to embed multiples of these into a file path (e.g., "/./././././././" is still the root). Technically, the "." may only refer to files that may contain other files (otherwise the term makes no sense). In canonical form, all "." will be resolved by simply being removed from the path. (For example, "/./foo/./bar/./." is "/foo/bar" in canonical form.)

The single period has another significant "feature". If a single period is placed at the start of a file name it takes on the Unix semantic of a "hidden file". Basically, all that means is that a glob wishing to match such a file must explicit start with a '.'.

=item ".."

The double period indicates the parent container. In the case of the root container, the root's parent is itself. In canonical form, all ".." will be resolved by replacing everything up to the ".." with the parent path. (For example, "/../foo/../bar/baz/.." is "/bar" in canonical form.)

=item "////"

All adjacent slashes are treated as a single slash. Thus, in canonical form, multiple adjacent slashes will be condenced into a single slash. (For example, "////foo//bar" is "/foo/bar" in canonical form.)

=item "?"

This character has special meaning in file globs. In a file glob it will match exactly one of any character. If you want to mean literally "?" instead, escape it with a backslash.

=item "*"

This character has special meaning in file globs. In a file glob it will match zero or more of any character non-greedily. If you want to mean literally "*" instead, escape it with a backslash.

=item "{a,b,c}"

The curly braces can be used to surround a comma separated list of alternatives in file globbing. If you mean a literal set of braces, then you need to escape them with a backslash.

=item "[abc0-9]"

The square brackets can be used to match any character within the given character class. If you mean a literal set of brackets, then you need to escape them with a backslash.

=back

=head1 FILE SYSTEM MODULE AUTHORS

If you want to write your own file system module, you will need to keep in mind a few things when implementing the various routines. File system module authors must implement at least two objects a L<File::System> module and a subclass of L<File::System::Object>. The former provides the doorway into the file system and the latter provides most of the actual functionality.

Every file system is comprised of records. In the typical modern file system, you will find at least two types of objects: files and directories. However, this is by no means the only kind of objects in a file system. There might also be links, devices, FIFOs, etc. Rather than try and anticipate all of the possible variations in file type, the basic idea has been reduced to a single object, L<File::System::Object>. Module authors should see the documentation there for additional details.

The records of a file system are generally organized in a heirarchy. It is possible for this heirarchy to have a depth of 1 (i.e., it's flat). To keep everything standard, file paths are always separated by the forward slash ("/") and a lone slash indicates the "root". Some systems provide multiple roots (usually called "volumes"). If a file system module wishes to address this problem, it should do so by artificially establishing an ultimate root under which the volumes exist.

In the heirarchy, the root has a special feature such that it is it's own parent. Any attempt to load the parent of the root, must load the root again. It should not be an error and it should never be able to reach some other object above the root (such as might be the case if a file system represents a "chroot" environment). Any other implementation is incorrect.

=head2 METHODS FOR MODULE AUTHORS

This class also provides a few helpers that may be useful to module uathors, but probably not of much use to typical users.

=over

=item $clean_path = $obj-E<gt>canonify($messy_path)

This method creates a canonical path out of the given path C<$messy_path>. This is the single most important method offered to module authors. It provides several things:

=over

=item 1.

If the path being canonified is relative, this method checks to see if the current object is a container. Paths are relative to the current object if the current object is container. Otherwise, the paths are relative to this object's parent.

=item 2.

Converts all relative paths to absolute paths.

=item 3.

Removes all superfluous '.' and '..' names so that it gives the most concise and direct name for the named file.

=item 4.

Enforces the principle that '..' applied to the root returns the root. This provides security by preventing users from getting to a file outside of the root (assuming that is possible for a given file system implementation).

=back

B<Module Authors:> Always, always, always use this method to clean up your paths.

=cut

sub canonify {
	my $self = shift;
	my $path = shift;

	# Skipped so we can still get some benefit in constructors
	if (ref $self && $path !~ m#^/#) {
		# Relative to me (I am a container) or to parent (I am not a container)
		$self->is_container
			or $self = $self->parent;
	
		# Fix us up to an absolute path
		$path = $self->path."/$path";
	}

	# Break into components
	my @components = split m#/+#, $path;
	@components = ('', '') unless @components;
	unshift @components, '' unless @components > 1;
	
	for (my $i = 1; $i < @components;) {
		if ($components[$i] eq '.') {
			splice @components, $i, 1;
		} elsif ($components[$i] eq '..' && $i == 1) {
			splice @components, $i, 1;
		} elsif ($components[$i] eq '..') {
			splice @components, ($i - 1), 2;
		} else {
			$i++;
		}
	}

	unshift @components, '' unless @components > 1;

	return join '/', @components;
}

=item @matched_paths = $obj-E<gt>match_glob($glob, @all_paths)

This will match the given glob pattern C<$glob> against the given paths C<@all_paths> and will return only those paths that match. This provides a de facto implementation of globbing so that any module can provide this functionality without having to invent this functionality or rely upon a third party module.

=cut

my $grammar = q(

glob:				match(s)

match:				match_one
|					match_any
|					match_alternative
|					match_collection
|					match_character

match_one: 			'?'
					{ 	$return = bless {}, 'File::System::Glob::MatchOne' }

match_any: 			'*'
					{ 	$return = bless {}, 'File::System::Glob::MatchAny' }

match_alternative:	'{' match_option(s /,/) '}'
					{ 	$return = bless { alternatives => $item[2] }, 'File::System::Glob::MatchAlternative' }

match_option:		/(?:[^,\\}\\\\]|\\\\}|\\\\,|\\\\)+/
					{ 	local $_ = $item[1];
						s/\\\\}/}/g;
						s/\\\\,/,/g;
						s/\\\\\\\\/\\\\/g;
						$return = $_ }

match_collection:  '[' match_class(s) ']'
					{	$return = bless { classes => $item[2] }, 'File::System::Glob::MatchCollection' }

match_class:		/(.)-(.)/
					{	$return = [ $1, $2 ] }
| 					/\\\\]/
					{	$return = "]" }
|					/[^\\]]/
					{	$return = $item[1] }

match_character:	/./
					{	$return = bless { character => $item[1] }, 'File::System::Glob::MatchCharacter' }

);

my $globber = Parse::RecDescent->new($grammar);

sub match_glob {
	my $self = shift;
	my $glob = shift;
	my @tree = @{ $globber->glob($glob) };
	my @paths = @_;

	my @matches;
	MATCH: for my $str (@paths) {
		# Special circumstance: any pattern not explicitly starting with '.'
		# cannot match a file name starting with '.'
		next if $str =~ /^\./ && $glob !~ /^\./;

		my $orig = $str;

		my @backup = ();
		my $tree = [ @tree ];
		while (my $el = shift @$tree) {
			if (ref $el eq 'File::System::Glob::MatchOne') {
				goto BACKUP unless substr $str, 0, 1, '';
			} elsif (ref $el eq 'File::System::Glob::MatchAny') {
				push @backup, [ $str, 0, @$tree ];
			} elsif (ref $el eq 'File::System::Glob::MatchAlternative') {
				my $match = 0;
				for my $alt (@{ $el->{alternatives} }) {
					if ($alt eq substr($str, 0, length($alt))) {
						substr $str, 0, length($alt), '';
						$match = 1;
						last;
					}
				}

				goto BACKUP unless $match;
			} elsif (ref $el eq 'File::System::Glob::MatchCollection') {
				my $char = substr $str, 0, 1, '';
				
				my $match = 0;
				for my $class (@{ $el->{classes} }) {
					if ((ref $class) && ($char ge $class->[0]) && ($char le $class->[1])) {
						$match = 1;
						last;
					} elsif ($char eq $class) {
						$match = 1;
						last;
					}
				}

				goto BACKUP unless $match;
			} else {
				my $char = substr $str, 0, 1, '';

				goto BACKUP unless $char eq $el->{character};
			}

			next unless $str and !@$tree;

BACKUP:		my ($tstr, $amt, @ttree);
			do {
				next MATCH unless @backup;
				($tstr, $amt, @ttree) = @{ pop @backup };
			} while (++$amt > length $tstr);

			push @backup, [ $tstr, $amt, @ttree ];

			$str  = substr $tstr, $amt;
			$tree = \@ttree;
		}

		push @matches, $orig;
	}

	return @matches;
}

=back

=head1 SEE ALSO

L<File::System>

=head1 AUTHOR

Andrew Sterling Hanenkamp, E<lt>hanenkamp@users.sourceforge.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2005 Andrew Sterling Hanenkamp. All Rights Reserved.

This software is distributed and licensed under the same terms as Perl itself.

=cut

1
