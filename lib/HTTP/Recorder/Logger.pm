package HTTP::Recorder::Logger;

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

sub GetScript {
    my $self = shift;

    if (open (SCRIPT, $self->{file})) {
	my @script = <SCRIPT>;
	close SCRIPT;
	return @script;
    } else {
	return undef;
    }
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

sub LogComment {
    my $self = shift;
    my $comment = shift;

    my $scriptfile = $self->{'file'};
    open (SCRIPT, ">>$scriptfile");
    print SCRIPT "# $comment\n";
    close SCRIPT;    
}

sub LogLine {
    my $self = shift;
    my %args = (
	line => "",
	@_
	);

    my $scriptfile = $self->{'file'};
    open (SCRIPT, ">>$scriptfile");
    print SCRIPT $args{line}, "\n";
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

    if ($args{text}) {
	$args{text} =~ s/"/\\"/g;
	$self->Log("follow_link", 
		   "text => \"$args{text}\", n => \"$args{index}\"");
    } else {
	$self->Log("follow_link", 
		   "n => \"$args{index}\"");
    }
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

    if ($args{name}) {
	$self->Log("submit_form", "form_name => \"$args{name}\"");
    } else {
	$self->Log("submit_form", "form_number => \"$args{index}\"");
    }
}

1;
