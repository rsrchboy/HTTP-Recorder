use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME         => 'HTTP::Recorder',
    VERSION_FROM => 'lib/HTTP/Recorder.pm', # finds $VERSION
    AUTHOR       => 'Linda Julien (leira@cpan.org)',
    PREREQ_PM	=> { LWP::UserAgent => 0,
                     HTML::TokeParser => 0,
                     URI::Escape => 0,
                   },
    ABSTRACT     => '',
);
