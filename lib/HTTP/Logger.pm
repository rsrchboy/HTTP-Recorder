package Test::Logger;

use strict;
use warnings;

sub new {
    my $class = shift;

    my %args = (
        file  => "/tmp/scriptfile",
	@_
    );

    my $self = bless ({}, ref ($class) || $class);

    $self->{'file'} = $args{'file'};

    return $self;
}

sub Log {
    my $self = shift;
    my $function = shift;
    my $args = shift;

    my $agentname = "\$agent";

    my $line = "$agentname->$function($args);\n";

    my $scriptfile = $self->{'file'};
    open (SCRIPT, ">>$scriptfile");
    print SCRIPT $line;
    close SCRIPT;
}

sub GotoPage {
    my $self = shift;
    my %args = (
	url => "",
	@_
	);

    $self->Log("get", "\"$args{url}\"");
}

sub FollowLink {
    my $self = shift;
    my %args = (
	text => "",
	index => "",
	@_
	);

    $self->Log("follow_link", 
	"text => \"$args{text}\", n => \"$args{index}\"");
}

sub SetField {
    my $self = shift;
    my %args = (
	@_
	);

    $self->Log("field", "\"$args{name}\", \"$args{value}\"");
}

sub Submit {
    my $self = shift;
    my %args = (
	@_
	);

    $self->Log("submit_form", "form_number => \"$args{index}\"");
}

1;
