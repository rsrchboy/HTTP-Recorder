package HTTP::Recorder::Logger;

use strict;
use warnings;
use LWP::MemberMixin;
our @ISA = qw( LWP::MemberMixin );

sub new {
    my $class = shift;

    my %args = (
	@_
    );

    my $self = bless ({}, ref ($class) || $class);

    $self->{'file'} = $args{'file'} || "/tmp/scriptfile";

    $self->{agentname} = "\$agent";

    return $self;
}

sub agentname { shift->_elem('agentname',      @_); }
sub file { shift->_elem('file',      @_); }

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

sub SetScript {
    my $self = shift;
    my $script = shift;

    my $scriptfile = $self->{'file'};
    open (SCRIPT, ">$scriptfile");
    print SCRIPT $script;
    close SCRIPT;
}

sub Log {
    my $self = shift;
    my $function = shift;
    my $args = shift;

    my $line = $self->{agentname} . "->$function($args);\n";

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

    $self->Log("get", "'$args{url}'");
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
		   "text => '$args{text}', n => '$args{index}'");
    } else {
	$self->Log("follow_link", 
		   "n => '$args{index}'");
    }
}

sub SetFieldsAndSubmit {
    my $self = shift;
    my %args = (
		name => "",
		number => undef,
		fields => {},
		button_name => {},
		button_value => {},
		button_number => {},
		@_
		);

    $self->SetForm(name => $args{name}, number => $args{number});
    foreach my $field (keys %{$args{fields}}) {
	$self->SetField(name => $field, 
			value => $args{fields}->{$field});
    }
    $self->Submit(name => $args{name}, 
		  number => $args{number},
		  button_name => $args{button_name},
		  button_value => $args{button_value},
		  button_number => $args{button_number},
		  );
}

sub SetForm {
    my $self = shift;
    my %args = (
	@_
	);

    if ($args{name}) {
	$self->Log("form_name", "'$args{name}'");
    } else {
	$self->Log("form_number", $args{number});
    }
}

sub SetField {
    my $self = shift;
    my %args = (
		name => undef,
		value => undef,
		@_
		);

    return unless $args{name} && $args{value};

    # escape single quotes
    $args{name} =~ s/'/\\'/g;
    $args{value} =~ s/'/\\'/g;

    $self->Log("field", "'$args{name}', '$args{value}'");
}

sub Submit {
    my $self = shift;
    my %args = (
	@_
	);

    # TODO: use button name, value, number
    # Don't add this until WWW::Mechanize supports it
    if ($args{name}) {
	$self->Log("submit_form", 
		   "form_name => '$args{name}', button => '$args{button_name}'");
    } else {
	$self->Log("submit_form", 
		   "form_number => $args{number}, button => '" .
		   ($args{button_name} || '') . "'");
    }
}

1;
