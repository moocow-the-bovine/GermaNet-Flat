use ExtUtils::MakeMaker;

WriteMakefile
  (
   NAME => 'GermaNet::Flat',
   AUTHOR => "Bryan Jurish <jurish@bbaw.de>",
   ABSTRACT => "Flat relational access to GermaNet data",
   VERSION_FROM	=> 'Flat.pm',

   EXE_FILES => [
		 glob('gn-flat-*.perl'),
		],
  );
