package HTTP::Recorder;

our $VERSION = "0.03_03";

=head1 NAME

HTTP::Recorder - record interaction with websites

=head1 VERSION

Version <0.03_03>

=head1 SYNOPSIS

Set HTTP::Recorder as the user agent for a proxy, and it rewrites HTTP
responses so that additional requests can be recorded.

Set it up like this:

    #!/usr/bin/perl

    use HTTP::Proxy;
    use HTTP::Recorder;

    my $proxy = HTTP::Proxy->new();

    # create a new HTTP::Recorder object
    my $agent = new HTTP::Recorder;

    # set the log file (optional)
    $agent->file("/tmp/myfile");

    # set HTTP::Recorder as the agent for the proxy
    $proxy->agent( $agent );

    # start the proxy
    $proxy->start();

    1;

Then, tell your web browser to use this proxy, and the script will be
recorded in the specified file.

=head2 SSL sessions

As of version 0.03, L<HTTP::Recorder> can record SSL sessions.

To begin recording an SSL session, go to the control URL
(http://http-recorder/ by default), and enter the initial URL.
Then, interact with the web site as usual.

=head2 Script output

By default, L<HTTP::Recorder> outputs L<WWW::Mechanize> scripts.

However, you can override HTTP::Recorder::Logger to output other types
of scripts.

=cut

use strict;
use warnings;
use LWP::UserAgent;
use HTML::TokeParser;
use HTTP::Recorder::Logger;
use URI::Escape qw(uri_escape uri_unescape);

our @ISA = qw( LWP::UserAgent );

=head1 Functions

=head2 new

Creates and returns a new L<HTTP::Recorder> object, referred to as the 'agent'.

=cut

sub new {
    my $class = shift;

    my %args = ( @_ );

    my $self = $class->SUPER::new( %args );
    bless $self, $class;

    $self->{prefix} = $args{prefix} || "rec";
    $self->{showwindow} = $args{showwindow} || 0;
    $self->{control} = $args{control} || "http-recorder";
    $self->{logger} = $args{logger} || 
	new HTTP::Recorder::Logger(file => $args{file});
    $self->{ignore_favicon} = $args{ignore_favicon} || 1;

    return $self;
}

=head2 $agent->prefix([$value])

Get or set the prefix string that L<HTTP::Recorder> uses for rewriting
responses.

=cut

sub prefix { shift->_elem('prefix',      @_); }

=head2 $agent->showwindow([0|1])

Get or set whether L<HTTP::Recorder> opens a JavaScript popup window,
displaying the recorder's control panel.

=cut

sub showwindow { shift->_elem('showwindow',      @_); }

=head2 $agent->control([$value])

Get or set the URL of L<HTTP::Recorder>'s control panel.  By default,
the control URL is 'http-recorder'.

The control URL will display a control panel which will allow you to
view and edit the current script.

=cut

sub control { shift->_elem('control',      @_); }

=head2 $agent->logger([$value])

Get or set the logger object.  The default logger is a
L<HTTP::Recorder::Logger>, which generates L<WWW::Mechanize> scripts.

=cut

sub logger { 
    my $self = shift;
    $self->_elem('logger',      @_);
}

=head2 B<$agent->ignore_favicon([0|1])>

Get or set ignore_favicon flag that causes L<HTTP::Recorder> to skip
logging requests which match /favicon\.ico$/.

=cut

sub ignore_favicon { shift->_elem('ignore_favicon',      @_); }

=head2 $agent->file([$value])

Get or set the filename for generated scripts.  The default is
'/tmp/scriptfile'.

=cut

sub file {
    my $self = shift;
    my $file = shift;

    $self->{logger}->file($file) if $file;
}

sub send_request {
    my $self = shift;
    my $request = shift;

    my $response;

    # special handling if the URL is the control URL
    if ($request->uri->host eq $self->{control}) {

	# get the arguments passed from the form
	my $arghash;
	$arghash = extract_values($request);
	
	# there may be an action we need to perform
	if (exists $arghash->{updatescript}) {
	    my $script = uri_unescape(@{$arghash->{ScriptContent}}[0]);
	    $self->{logger}->SetScript($script || '');
	} elsif (exists $arghash->{clearscript}) {
	    $self->{logger}->SetScript("");
	} elsif (exists $arghash->{goto}) {
	    my $url = uri_unescape(@{$arghash->{url}}[0]);

	    my $r = new HTTP::Request("GET", $url);
	    my $response = $self->send_request( $r );

	    return $response;
	}
	
	my ($h, $content);
	if (exists $arghash->{savescript}) {
	    $h = HTTP::Headers->new(Content_Type => 'text/plain');
	    my @script = $self->{logger}->GetScript();
	    $content = join('', @script);
	} else {
	    $h = HTTP::Headers->new(Content_Type => 'text/html');
	    $content = $self->get_recorder_content();
	}

	$response = HTTP::Response->new(200,
					"",
					$h,
					$content,
					);
    } else {
	$request = $self->modify_request ($request)
            unless $self->{ignore_favicon}
                && $request->uri->path =~ /favicon\.ico$/i;

	$response = $self->SUPER::send_request( $request );

	my $content_type = $response->headers->header('Content-type') || "";

	# don't try to modify the content unless it's text/<something>
	if ($content_type =~ m#^text/#i) {
	    $self->modify_response($response);
	}
    }

    return $response;
}

sub modify_request {
    my $self = shift;
    my $request = shift;

    my $values = extract_values($request);

    # log the actions
    my $action = @{$values->{"$self->{prefix}-action"}}[0];

    my $referer = $request->headers->referer;
    if (!$action) {
	if (!$referer) {
	    my $uri = $request->uri;
	    $self->unmodify(\$uri);

	    # log a blank line to give the code a little breathing room
	    $self->{logger}->LogLine();
	    $self->{logger}->GotoPage(url => $uri);
	}
    } elsif ($action eq "follow") {
	$self->{logger}->FollowLink(text => @{$values->{"$self->{prefix}-text"}}[0] || "",
			    index => @{$values->{"$self->{prefix}-index"}}[0] || "",
			    url => @{$values->{"$self->{prefix}-url"}}[0]);
    } elsif ($action eq "submitform") {
	my %fields;
	my ($btn_name, $btn_value, $btn_number);
	foreach my $param (keys %$values) {
	    my %fieldhash;
	    my ($fieldtype, $fieldname);
	    if ($param =~ /^$self->{prefix}-form(\d+)-(\w+)-(.*)$/) {
		$fieldtype = $2;
		$fieldname = $3;

		if ($fieldtype eq 'submit') {
		    next unless $values->{$fieldname};
		    $btn_name = $fieldname;
		    $btn_value = $values->{$fieldname};
		} else {
		    next if ($fieldtype eq 'hidden');
		    next unless $fieldname && exists $values->{$fieldname}[0];
		    $fieldhash{'name'} = $fieldname;
		    $fieldhash{'type'} = $fieldtype;
		    my @tempvalues = @{$values->{$fieldname}};
		    if ($fieldtype eq 'checkbox') {
			for (my $i = 0 ; $i < scalar @tempvalues ; $i++) {
			    $fieldhash{'value'} = $tempvalues[$i];
			    $fields{"$fieldname-$i"} = \%fieldhash;
			}
		    } else {
			$fieldhash{'value'} = $tempvalues[0];
			$fields{$fieldname} = \%fieldhash;
		    }
		}
	    }
	}

	$self->{logger}->SetFieldsAndSubmit(name => @{$values->{"$self->{prefix}-formname"}}[0], 
					    number => @{$values->{"$self->{prefix}-formnumber"}}[0],
					    fields => \%fields,
					    button_name => $btn_name,
					    button_value => $btn_value);

	# log a blank line to give the code a little breathing room
	$self->{logger}->LogLine();
    }

    # undo what we've done
    $request->uri($self->unmodify($request->uri));
    $request->content($self->unmodify($request->content));

    # reset the Content-Length (if needed) to prevent warnings from
    # HTTP::Protocol
    if ($action && ($action eq "submitform")) {
	$request->headers->header('Content-Length' => length($request->content()) );
	
    }

    my $https = $values->{"$self->{prefix}-https"};
    if ( $https && $https == 1) {
	my $uri = $request->uri;
	$uri =~ s/^http:/https:/i;

	$request = new HTTP::Request($request->method, 
				     $uri, 
				     $request->headers, 
				     $request->content);
	
    }	    

    return $request;
}

sub unmodify {
    my $self = shift;
    my $content = shift;

    return $content unless $content;

    # get rid of the stuff we added
    my $prefix = $self->{prefix};

    $content =~ s/$prefix-(.*?)\?(.*?)&//g;
    $content =~ s/$prefix-(.*?)&//g;
    $content =~ s/$prefix-(.*?)$//g;
    $content =~ s/&$//g;
    $content =~ s/\?$//g;

    return $content;
}

sub extract_values {
    my $request = shift;

    my $values = {};

    if ($request->headers->content_type eq 'multipart/form-data') {
	my $content = $request->content;
	my @segments = split(/--+/, $content);
	foreach (@segments) {
	    next unless $_;
	    $_ =~ s/.*Content-Disposition: //s;
	    $_ =~ s/\r+/\n/sg;
	    $_ =~ s/\n+/; /sg;
	    my @fields = split(/; /, $_);
	    next unless $fields[1];
	    $fields[1] =~ s/name="(.*)"/$1/g;
	    next unless exists $fields[2];
	    if ($fields[2] =~ m/^filename/) {
		$fields[2] = "file here!!";
	    } else {
		$fields[2] =~ s/\n//sg;
	    }
	    push (@{$values->{$fields[1]}}, $fields[2]);

	}
    }

    my $content;
    if ($request->method eq "POST") {
	$content = $request->content;
    } else {
	my @foo = split(/\?/,$request->uri);
	$content = $foo[1];
    }

    return () unless defined $content;

    my(@parts, $key, $val);

    if ($content =~ m/=/ or $content =~ m/&/) {

        $content =~ tr/+/ /;      # RFC1630
        @parts = split(/&/, $content);

        foreach (@parts) { # Extract into key and value.
            ($key, $val) = m/^(.*?)=(.*)/;
            $val = (defined $val) ? uri_unescape($val) : '';
            $key = uri_unescape($key);

	    push (@{$values->{$key}}, $val) if defined $val;
	}
    }

    return $values;
}

sub modify_response {
    my $self = shift;
    my $response = shift;
    my $formcount = 0;
    my $formnumber = 0;
    my $linknumber = 1;

    $response->headers->push_header('Cache-Control', 'no-store, no-cache');
    $response->headers->push_header('Pragma', 'no-cache');

    my $content = $response->content();
    my $p = HTML::TokeParser->new(\$content);
    my $newcontent = "";
    my %links;
    my $formname;

    my $js_href = 0;
    my $in_head = 0;
    my $basehref;
    while (my $token = $p->get_token()) {
	if (@$token[0] eq 'S') {
	    my $tagname = @$token[1];
	    my $attrs = @$token[2];
	    my $oldaction;
	    my $text;

	    if ($tagname eq 'head') {
		$in_head = 1;
	    } elsif ($in_head && $tagname eq 'base') {
		$basehref = new URI($attrs->{'base'});
	    } elsif ($tagname eq 'html') {
		if ($self->{showwindow}) {
		    $newcontent .= $self->script_popup();
		}
	    } elsif (($tagname eq 'a' || $tagname eq 'link') && 
		     $attrs->{'href'}) {
		my $t = $p->get_token();
		if (@$t[0] eq 'T') {
		    $text = @$t[1];
		} else {
		    undef $text;
		}
		$p->unget_token($t);

		# up the counter for links with the same text
		my $index;
		if (defined $text) {
		    $links{$text} = 0 if !(exists $links{$text});
		    $links{$text}++;
		    $index = $links{$text};
		} else {
		    $index = $linknumber;
		}
		if ($attrs->{'href'} =~ m/^javascript:/i) {
		    $js_href = 1;
		} else {
		    if ($tagname eq 'a') {
			$attrs->{'href'} = 
			    $self->rewrite_href($attrs->{'href'}, 
						$text, 
						$index,
						$response->base);
		    } elsif ($tagname eq 'link') {
			$attrs->{'href'} = 
			    $self->rewrite_linkhref($attrs->{'href'}, 
						    $response->base);
		    }
		}
		$linknumber++;
	    } elsif ($tagname eq 'form') {
		$formcount++;
		$formnumber++;
	    }

	    # put the hidden field before the real field
	    # so that it won't be inside
	    if (!$js_href && 
		$tagname ne 'form' && ($formcount == 1)) {
		my ($formfield, $fieldprefix, $fieldtype, $fieldname);
		$fieldprefix = "$self->{prefix}-form" . $formnumber;
		$fieldtype = lc($attrs->{type}) || 'unknown';
		if ($attrs->{name}) {
		    $fieldname = $attrs->{name};
		    $formfield = ($fieldprefix . '-' . 
				  $fieldtype . '-' . $fieldname);
		    $newcontent .= "<input type=\"hidden\" name=\"$formfield\" value=1>\n";
		}
	    }

	    $newcontent .= ("<".$tagname);

	    # keep the attributes in their original order
	    my $attrlist = @$token[3];
	    foreach my $attr (@$attrlist) {
		# only rewrite if 
		# - it's not part of a javascript link
		# - it's not a hidden field
		$newcontent .= (" ".$attr."=\"".$attrs->{$attr}."\"");
	    }
	    $newcontent .= (">\n");
	    if ($tagname eq 'form') {
		if ($formcount == 1) {
		    $newcontent .= $self->rewrite_form_content($attrs->{name} || "",
							       $formnumber,
							       $response->base);
		}
	    }
	} elsif (@$token[0] eq 'E') {
	    my $tagname = @$token[1];
	    if ($tagname eq 'head') {
		if (!$basehref) {
		    $basehref = $response->base;
		    $basehref->scheme('http') if $basehref->scheme eq 'https';
		    $newcontent .= "<base href=\"" . $basehref . "\">\n";
		}
		$basehref = "";
		$in_head = 0;
	    }
	    $newcontent .= ("</");
	    $newcontent .= ($tagname.">\n");
	    if ($tagname eq 'form') {
		$formcount--;
	    } elsif ($tagname eq 'a' || $tagname eq 'link') {
		$js_href = 0;
	    }
	} elsif (@$token[0] eq 'PI') {
	    $newcontent .= (@$token[2]);
	} else {
	    $newcontent .= (@$token[1]);
	}
    }

    $response->content($newcontent);

    return;
}

sub rewrite_href {
    my $self = shift;
    my $href = shift || "";
    my $text = shift || "";
    my $index = shift || 1;
    my $url = shift;

    my @parts = split(/\?/, $href);
    my $realhref = uri_escape($href);
    my $realargs = $parts[1] || "";
    my $base = $parts[0];

    my $https = 0;
    $https = 1 if $url->scheme eq 'https';

    # the link text might have special characters in it
    $text = uri_escape($text);

    # figure out if the link is an anchor on the same page
    my $anchor;
    if ($href =~ m/^#/) {
	$anchor = $href;
	$base = "";
    }

    $href = "$base?$self->{prefix}-url=$realhref";
    $href .= "&$self->{prefix}-https=$https" if $https;
    $href .= "&$realargs" if $realargs;
    $href .= "&$self->{prefix}-action=follow";
    $href .= "&$self->{prefix}-text=$text";
    $href .= "&$self->{prefix}-index=$index";
    $href .= $anchor if $anchor;

    return $href;
}

sub rewrite_linkhref {
    my $self = shift;
    my $href = shift || "";
    my $url = shift;

    my @parts = split(/\?/, $href);
    my $realhref = uri_escape($href);
    my $realargs = $parts[1] || "";

    my $https = 0;
    $https = 1 if $url->scheme eq 'https';
    my $base = $parts[0];

    # figure out if the link is an anchor on the same page
    my $anchor;
    if ($href =~ m/^#/) {
	$anchor = $href;
	$base = "";
    }

    $href = "$base?$self->{prefix}-url=$realhref";
    $href .= "&$self->{prefix}-https=$https" if $https;
    $href .= "&$realargs" if $realargs;
    $href .= "&$self->{prefix}-action=norecord";
    $href .= $anchor if $anchor;

    return $href;
}

sub rewrite_form_content {
    my $self = shift;
    my $name = shift || "";
    my $number = shift;
    my $fields;
    my $url = shift;

    my $https = 1 if ($url =~ m/^https/i);

    $fields .= ("<input type=hidden name=\"$self->{prefix}-action\" value=\"submitform\">\n");
    $fields .= ("<input type=hidden name=\"$self->{prefix}-formname\" value=\"$name\">\n");
    $fields .= ("<input type=hidden name=\"$self->{prefix}-formnumber\" value=\"$number\">\n");
    if ($https) {
    $fields .= ("<input type=hidden name=\"$self->{prefix}-https\" value=\"$https\">\n");
    }

    return $fields;
}

sub get_recorder_content {
    my $self = shift;

    my @script = $self->{logger}->GetScript();
    my $script = "";
    foreach my $line (@script) {
	next unless $line;
	$line =~ s/\n//g;
	$script .= "$line\n";
    }

    my $content = <<EOF;
<SCRIPT LANGUAGE="JavaScript">
<!-- // start
function scrollScriptAreaToEnd() {
    scriptarea = document.forms['ScriptForm'].elements['ScriptContent'];
    scriptarea.scrollTop = scriptarea.scrollHeight;
    scriptarea.focus();
}
// end -->
</SCRIPT>

<html>
<body bgcolor="lightgrey" onLoad="javascript:scrollScriptAreaToEnd()">
<FORM name="ScriptForm" method="POST" action="http://$self->{control}/">
<table width=100% height=98%>
  <tr>
    <td>
Goto page: <input name="url" size=40>
<input type=submit name="goto" value="Go">
    </td>
  </tr>
  <tr>
    <td>
Current Script:
    </td>
  </tr>
  <tr>
    <td height=100%>
      <textarea style="font-size: 10pt;font-family:monospace;width:100%;height:100%" name="ScriptContent">
$script
</textarea>
    </td>
  </tr>
  <tr>
    <td align=center>
      <INPUT TYPE="BUTTON" VALUE="Refresh" onClick="window.location='http://$self->{control}/'">
      <INPUT TYPE="SUBMIT" name="updatescript" VALUE="Update">
      <INPUT TYPE="SUBMIT" name="clearscript" VALUE="Delete"
      onClick="if (!confirm('Do you really want to delete the script?')){ return false; }">
      <INPUT TYPE="RESET">
      <INPUT TYPE="SUBMIT" name="savescript" VALUE="Download">
    </td>
  </tr>
  <tr>
    <td align=center>
      <INPUT TYPE="BUTTON" VALUE="Close Window" onClick="self.close()">
    </td>
  </tr>
</table>
</body></html>
EOF

    return $content;
}

sub script_popup {
    my $self = shift;

    my $url = "http://" . $self->control . "/";
    my $js = <<EOF;
mywin = window.open("$url", "script", "width=400,height=400,toolbar=no,scrollbars=yes,resizable=yes");
EOF

return <<EOF;
<SCRIPT LANGUAGE="JavaScript">
<!-- // start
$js
// end -->
</SCRIPT>
EOF
}

=head1 Bugs, Missing Features, and other Oddities

=head2 Javascript

L<HTTP::Recorder> won't record Javascript actions.

=head2 Why are my images corrupted?

HTTP::Recorder only tries to rewrite responses that are of type
text/*, which it determines by reading the Content-Type header of the
HTTP::Response object.  However, if the received image gives the
wrong Content-Type header, it may be corrupted by the recorder.  While
this may not be pleasant to look at, it shouldn't have an effect on
your recording session.

=head1 See Also

See also L<LWP::UserAgent>, L<WWW::Mechanize>, L<HTTP::Proxy>.

=head1 Requests & Bugs

Please submit any feature requests, suggestions, bugs, or patches at
http://rt.cpan.org/, or email to bug-HTTP-Recorder@rt.cpan.org.

=head1 Mailing List

There's a mailing list for users and developers of HTTP::Recorder.
You can subscribe at
http://lists.fsck.com/mailman/listinfo/http-recorder, or by sending
email to http-recorder-request@lists.fsck.com with the subject
"subscribe".

The archives can be found at
http://lists.fsck.com/pipermail/http-recorder.

=head1 Author

Copyright 2003-2005 by Linda Julien <leira@cpan.org>

Released under the GNU Public License.

=cut

1;
