use strict;

use Module::Build;

my $build = Module::Build->new(
	module_name => 'File::System',
	license     => 'perl',
	requires    => {
		'File::Copy::Recursive' => '0.05',
		'Parse::RecDescent'     => 1.94,
	},
);

$build->create_build_script;
