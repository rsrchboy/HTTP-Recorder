package HTTP::Recorder;

=head1 NAME

HTTP::Recorder - record interaction with websites

=head1 VERSION

Version 0.02

=cut

our $VERSION = "0.02";

=head1 SYNOPSIS

Set HTTP::Recorder as the user agent for a proxy, and it rewrites HTTP
responses so that additional requests can be recorded.

Set it up like this:

    my $proxy = HTTP::Proxy->new;

    # set HTTP::Recorder as the agent
    my $agent = HTTP::Recorder->new( file => "/tmp/tmpfile",
				     showwindow => 1);
    $proxy->agent( $agent );

    # you may need to set the host
    # $proxy->host( "www.example.com" );

    $proxy->start();

Then, tell your web browser to use your proxy, and the script will be
recorded in the specified file.

If showwindow is set to 1, a popup window will display the current
script after each action.

=head2 Javascript & SSL

HTTP::Recorder won't record Javascript actions, or pages delivered via
SSL.

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
our ($Logger, $prefix, $showwindow);

=head1 Functions

=head2 B<new>

Creates and returns a new L<HTTP::Recorder> object, referred to as the 'agent'.

=cut

sub new {
    my $class = shift;

    my %args = (
		showwindow  => 0,
		file  => "",
		prefix => "rec",
		@_
		);

    my $self = $class->SUPER::new( %args );
    bless $self, $class;

    $prefix = $args{prefix};
    $showwindow = $args{showwindow};

    if ($args{logger}) {
	$Logger = $args{logger};
    } else {
	$Logger = new HTTP::Recorder::Logger(file => $args{file});
    }

    return $self;
}

sub send_request {
    my $self = shift;
    my $request = shift;

    modify_request ($request);

    my $response = $self->SUPER::send_request( $request );

    my $content_type = $response->headers->header('Content-type') || "";

    # don't try to modify the content unless it's text/<something>
    if ($content_type =~ m#^text/#i) {
	modify_response($response);
    }

    return $response;
}

sub modify_request {
    my $request = shift;

    # get the name/value pairs from the body
    my $args = $request->content;

    # get the name/value pairs from the url
    my @parts = split(/\?/, $request->uri);

    # concatenate them and extract key/value pairs
    $args .= "&" if $args;
    $args .= $parts[1] if $parts[1];
    my $values = extract_values($args);

    # log the actions
    my $action = $values->{"$prefix-action"};
    my $referer = $request->headers->referer;
    if (!$action) {
	if (!$referer) {
	    my $uri = $request->uri;
	    unmodify(\$uri);

	    # log a blank line to give the code a little breathing room
	    $Logger->LogLine();

	    $Logger->GotoPage(url => $uri);
	}
    } elsif ($action eq "follow") {
	$Logger->FollowLink(text => $values->{"$prefix-text"} || "",
			    index => $values->{"$prefix-index"} || "",
			    url => $values->{"$prefix-index"});
    } elsif ($action eq "submitform") {
	foreach my $param (keys %$values) {
	    if ($param =~ /^$prefix-form-(\d+)-(.*?)$/) {
		my $temp = $param;
		$temp =~ s/^$prefix-form-(\d+)-//g;
		$Logger->SetField(name => $temp,
				  value => $values->{$temp},
				  );
	    }
	}

	$Logger->Submit(name => $values->{"$prefix-formname"}, 
			index => $values->{"$prefix-formnumber"});

	# log a blank line to give the code a little breathing room
	$Logger->LogLine();
    }

    # undo what we've done
    $request->uri(unmodify($request->uri));
    $request->content(unmodify($request->content));

    # reset the Content-Length (if needed) to prevent warnings from
    # HTTP::Protocol
    if ($action && ($action eq "submitform")) {
	$request->headers->header('Content-Length' => length($request->content()) );
	
    }
}

sub unmodify {
    my $content = shift;

    # get rid of the stuff we added
    $content =~ s/($prefix-form-(\d+)-)//g;
    $content =~ s/$prefix-(.*?)\?(.*?)&//g;
    $content =~ s/$prefix-(.*?)&//g;
    $content =~ s/$prefix-(.*?)$//g;
    $content =~ s/\?$//g;

    return $content;
}

sub extract_values {
    my $content = shift;

    my $values = {};

    return () unless defined $content;

    my(@parts, $key, $val);

    if ($content =~ m/=/ or $content =~ m/&/) {

        $content =~ tr/+/ /;      # RFC1630
        @parts = split(/&/, $content);

        foreach (@parts) { # Extract into key and value.
            ($key, $val) = m/^(.*?)=(.*)/;
            $val = (defined $val) ? uri_unescape($val) : '';
            $key = uri_unescape($key);
	    
	    $values->{$key} = $val if $val;
        }
    }

    return $values;
}

sub modify_response {
    my $response = shift;
    my @forms;
    my $formnumber = 0;
    my $linknumber = 1;

    $response->headers->push_header('Cache-Control', 'no-store, no-cache');
    $response->headers->push_header('Pragma', 'no-cache');

    my $content = $response->content();
    my $p = HTML::TokeParser->new(\$content);
    my $newcontent = "";
    my %links;

    my $isjs = 0;
    my $formfield = "";
    while (my $token = $p->get_token()) {
	if (@$token[0] eq 'S') {
	    my $tagname = @$token[1];
	    my $attrs = @$token[2];
	    my $oldaction;
	    my $text;

	    if ($tagname eq 'html') {
		if ($showwindow) {
		    $newcontent .= script_popup("la la la");
		}
	    } elsif ($tagname eq 'a' && $attrs->{'href'}) {
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
		    $isjs = 1;
		} else {
		    $attrs->{'href'} = rewrite_href($attrs->{'href'}, 
						    $text, 
						    $index);
		}
		$linknumber++;
	    } elsif ($tagname eq 'form') {
		push @forms, $token;
		$formnumber++;
	    }
	    $newcontent .= ("<".$tagname);

	    # keep the attributes in their original order
	    my $attrlist = @$token[3];
	    foreach my $attr (@$attrlist) {
		# only rewrite if 
		# - it's not part of a javascript link
		# - it's not a hidden field
		if (!$isjs && 
		    $attr eq 'name' && $tagname ne 'form' 
		    && scalar @forms == 1) {
		    $formfield = ("$prefix-form-".
				  $formnumber."-".$attrs->{$attr});
		}
		$newcontent .= (" ".$attr."=\"".$attrs->{$attr}."\"");
	    }
	    $newcontent .= (">\n");
	    if ($formfield) {
		$newcontent .= "<input type=\"hidden\" name=\"$formfield\" value=1>\n";
		$formfield = "";
	    }
	    if ($tagname eq 'form') {
		if (scalar @forms == 1) {
		    $newcontent .= rewrite_form_content($attrs->{name}, 
							$formnumber);
		}
	    }
	} elsif (@$token[0] eq 'E') {
	    $newcontent .= ("</");
	    my $tagname = @$token[1];
	    $newcontent .= ($tagname.">\n");
	    if ($tagname eq 'form') {
		pop @forms;
	    } elsif ($tagname eq 'a') {
		$isjs = 0;
	    }
	} else {
	    $newcontent .= (@$token[1]);
	}
    }

    $response->content($newcontent);

    return;
}

sub rewrite_href {
    my $href = shift || "";
    my $text = shift || "";
    my $index = shift || 1;

    my @parts = split(/\?/, $href);
    my $realhref = uri_escape($href);
    my $realargs = $parts[1] || "";

    # the link text might have special characters in it
    $text = uri_escape($text);

    # this does not deal with anchored links at all. 
    $href =~ s/(.*)/$parts[0]?$prefix-action=follow&$prefix-text=$text&$prefix-index=$index&$prefix-url=$realhref&$realargs/;

    return $href;
}

sub rewrite_form_content {
    my $name = shift || "";
    my $number = shift;
    my $fields;

    $fields .= ("<input type=hidden name=\"$prefix-action\" value=\"submitform\">\n");
    $fields .= ("<input type=hidden name=\"$prefix-formname\" value=\"$name\">\n");
    $fields .= ("<input type=hidden name=\"$prefix-formnumber\" value=\"$number\">\n");

    return $fields;
}

sub script_popup {
    my $js = <<EOF;
mywin = window.open("", "script", "height=400,width=400,toolbar=no,scrollbars=yes,resizable=yes");
mywin.document.open();
mywin.document.write('<HTML><BODY>\\n');
mywin.document.write('<FORM>\\n');
mywin.document.write('<table>\\n');
mywin.document.write('  <tr>\\n');
mywin.document.write('    <th>\\n');
mywin.document.write('      Current script\\n');
mywin.document.write('    </th>\\n');
mywin.document.write('  </tr>\\n');
mywin.document.write('  <tr>\\n');
mywin.document.write('    <td align=center>\\n');
mywin.document.write('      <TEXTAREA name="UpdateScript" cols=55 rows=20>');
EOF

    my @script = $Logger->GetScript();
    foreach my $line (@script) {
	next unless $line;
	$line =~ s/\n//g;
	$line =~ s/'/\\'/g;
	$js .= "mywin.document.write('$line\\n');\n";
    }

#mywin.document.write('        <td><INPUT TYPE=\"SUBMIT\" name=\"updatescript\" VALUE=\"Update\"></td>\\n');
#mywin.document.write('        <td><INPUT TYPE=\"SUBMIT\" name=\"clearscript\" VALUE=\"Clear\"></td>\\n');
#mywin.document.write('        <td><INPUT TYPE=\"RESET\"></td>\\n');
#mywin.document.write('      <a href="$prefix-action=savescript">Download</a>\\n');

    $js .= <<EOF;
mywin.document.write('</TEXTAREA>');
mywin.document.write('    </td>\\n');
mywin.document.write('  </tr>\\n');
mywin.document.write('  <tr>\\n');
mywin.document.write('    <td align=center>\\n');
mywin.document.write('      <table><tr>\\n');
mywin.document.write('        <td><INPUT TYPE=\"BUTTON\" VALUE="Close Window" onClick="self.close()"></td>\\n');
mywin.document.write('      </tr></table>\\n');
mywin.document.write('    </td>\\n');
mywin.document.write('  </tr>\\n');
mywin.document.write('  <tr>\\n');
mywin.document.write('    <td align=center>\\n');
mywin.document.write('    </td>\\n');
mywin.document.write('  </tr>\\n');
mywin.document.write('<table>\\n');
mywin.document.write('</FORM>\\n');
mywin.document.write('</BODY></HTML>\\n');
mywin.document.close();
EOF

return <<EOF;
<SCRIPT LANGUAGE="JavaScript">
<!-- // start
$js
// end -->
</SCRIPT>
EOF
}

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

Copyright 2003-2004 by Linda Julien <leira@cpan.org>

Released under the GNU Public License.

=cut

1;
