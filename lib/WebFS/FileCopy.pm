package WebFS::FileCopy;

require 5.004_04;

use strict;
use Exporter;
use Carp qw(croak cluck);
use Cwd;
use LWP::Version 0.21;
use LWP::UA;
use LWP::MainLoop qw(mainloop);
use HTTP::Request::Common qw(GET PUT);
use Net::FTP;
require LWP::Version;
require LWP::Conn::HTTP;
require LWP::Request;
require WebFS::FileCopy::Put;

use vars qw($VERSION @ISA @EXPORT $ua);

$VERSION = do {my @r=(q$Revision: 0.02 $=~/\d+/g);sprintf "%d."."%02d"x$#r,@r};
@ISA     = qw(Exporter);
@EXPORT  = qw(&copy_url &copy_urls &delete_urls &get_urls &list_url
	      &move_url &put_urls);

# Make sure that we have version 0.21 or greater of LWP::Version from
# LWPng.
BEGIN {
  if ($LWP::Version::VERSION < 0.21) {
    Carp::croak("WebFS::FileCopy requires LWP::Version version 0.21 or greater\n");
  }
}

package LWP::UA;
use Carp qw(cluck);
use LWP::MainLoop qw(mainloop);
sub _start_read_request {
  my ($self, $req) = @_;

  bless $req, 'LWP::Request' if ref($req) eq 'HTTP::Request';

  my $res;
  $req->{data_cb} = sub {
    $res = $_[1];
    $res->add_content($_[0]);
  };
  $req->{done_cb} = sub {
    $res = shift;
    $res->{done}++;
  };

  $self->spool($req);

  mainloop->one_event until $res || mainloop->empty;

  bless $res, 'LWP::Response';
}

sub _start_transfer_request {
  my $self = shift;

  unless (@_ > 1) {
    cluck "WebFS::FileCopy::_start_transfer_request passed two few arguments";
    return;
  }

  # Create and submit the GET request.
  my $get_req = shift;
  my $get_res = $self->_start_read_request($get_req);

  my @put_req = @_;

  # Check the response.
  return $get_res unless $get_res->is_success;

  # This array holds the file: or ftp: objects that support print and
  # close methods on the outgoing data.  Is the put fails, then hold the
  # response placed into $@.  Keep track that the responses for each PUT
  # are in the same order as the requests.
  my @put_connections = ();
  my @put_res = ();
  my $i = 0;
  foreach my $put_req (@put_req) {
    my $conn = WebFS::FileCopy::Put->new($put_req);
    if ($conn) {
      $put_connections[$i] = $conn;
      $put_res[$i]         = undef;
    }
    else {
      $put_connections[$i] = undef;
      $put_res[$i]         = $@;
    }
    ++$i;
  }

  # This subroutine writes the current get contents to the output handles.
  my $print_sub = sub {
    my $get_res = shift;
    my $buffer = $get_res->content('');
    return unless length($buffer);
    foreach my $put_conn (@put_connections) {
      next unless $put_conn;
      $put_conn->print($buffer);
    }
  };

  my $data_cb_sub = sub {
    $get_res = $_[1];
    $get_res->add_content($_[0]);
    &$print_sub($get_res);
  };

  my $done_cb_sub = sub {
    $get_res = shift;
    $get_res->{done}++;
    &$print_sub($get_res);
    # Add the HTTP::Response for closing each put.
    my $i = -1;
    foreach my $put_conn (@put_connections) {
      ++$i;
      next unless $put_conn;
      $put_res[$i] = $put_conn->close;
    }
    $get_res->{put_requests} = \@put_res;
  };

  # Update the callbacks to handle the new data transfer.
  $get_req->{data_cb} = $data_cb_sub;
  $get_req->{done_cb} = $done_cb_sub;

  # The gets may already be completed at this point.  If this is so, then
  # send the data to the outgoing URLs and close up.
  &$done_cb_sub($get_res) if exists($get_res->{done});

  $get_res;
}

package LWP::Response;
use base 'HTTP::Response';
use LWP::MainLoop qw(mainloop);

sub _read_content {
  my $self = shift;

  my $c = $self->content('');
  return $c if length($c);

  return if $self->{done};

  # Now wait for more data.
  my $data;
  $self->request->{data_cb} = sub { $data = $_[0]; };
  mainloop->one_event until
    mainloop->empty || defined($data) || $self->{done};

  $data;
}

package WebFS::FileCopy;

sub _init_ua {
  # Create a global UserAgent object.
  $ua = LWP::UA->new ;
  $ua->env_proxy;
}

# Take either an URI::URL or a string URL and make it into an absolute
# URI::URL.  Do not touch the given URL.  If the URL is missing a scheme,
# then assume it to be file and if the file path is not an absolute one,
# then assume that the current directory contains the file.
sub _fix_url {
  my $url  = shift;
  my $base = shift;

  # Fix the URL.
  if (ref($url)) {
    $url = $url->clone->abs($base);
  }
  else {
    my $temp = $url;
    $url = eval { URI::URL->new($url, $base); };
    cluck "WebFS::FileCopy::_fix_url failed on $temp" if $@;
#    if (!$url->scheme and $url->path) {
#      $url->scheme('file');
#      my $path = $url->epath;
#      $url->epath(cwd . "/$path") unless $path =~ m:^/:;
#    }
  }
  $url;
}

# Take a URL and return if the URL is a directory or a file.  A directory
# always ends in /.
sub _is_directory {
  my $url = shift;
  my $base = shift;

  $url = _fix_url($url, $base);
  return $url ? ($url->path =~ m:/$:) : undef;
}

sub get_urls {
  return () unless @_;

  my @urls = @_;

  _init_ua unless $ua;

  # Quickly spool each GET request.
  my @get_req = ();
  my @get_res = ();
  my $i = 0;
  foreach my $url (@urls) {
    $url = _fix_url($url);
    my $get_req = LWP::Request->new('GET' => $url);

    # $j is created here to be local to this loop and recorded in each
    # anonymous subroutine created below.
    my $j = $i;

    $get_res[$j] = undef;
    $get_req->{data_cb} = sub {
      $get_res[$j] = $_[1];
      $get_res[$j]->add_content($_[0]);
    };
    $get_req->{done_cb} = sub {
      $get_res[$j] = shift;
      $get_res[$j]->{done}++;
    };
    $ua->spool($get_req);
    $get_req[$j] = $get_req;
    ++$i;
  }

  # Perform one_event() until all of the done requests are handled.
  while (1) {
    my $done = 1;
    foreach my $get_res (@get_res) {
      unless (defined($get_res) and exists($get_res->{done})) {
        $done = 0;
        last;
      }
    }
    last if $done || mainloop->empty;
    mainloop->one_event;
  }

  # Return the responses.
  @get_res;
}

sub put_urls {
  unless (@_ >= 2) {
    $@ = 'Too few arguments';
    cluck $@;
    return;
  }

  my $string_or_code = shift;

  # Convert string URLs to URI::URLs.
  my @urls = map { _fix_url($_) } @_;

  # This holds the responses for each PUT request.
  my @put_res = ();

  # Go through each URL and create a request for it if the URL is ok.
  my @put_req = ();
  my $leave_now = 1;
  foreach my $url (@urls) {
    my $put_req = LWP::Request->new('PUT' => $url);

    # We put this in so that gen_response can be used.
    $put_req->{done_cb} = sub { $_[0]; };

    # Need a valid URL.
    unless ($url) {
      push(@put_req, 0);
      push(@put_res,
        $put_req->gen_response(400, 'Missing URL in request'));
      next;
    }

    # URL cannot be a directory.
    if (_is_directory($url)) {
      push(@put_req, 0);
      push(@put_res,
        $put_req->gen_response(403, 'URL cannot be a directory'));
      next;
    }

    # URL scheme needs to be either ftp or file.
    my $scheme = $url->scheme;
    unless ($scheme && ($scheme eq 'ftp' or $scheme eq 'file')) {
      push(@put_req, 0);
      push(@put_res,
        $put_req->gen_response(400, "Invalid scheme $scheme"));
      next;
    }

    # We now have a valid request.
    push(@put_req, $put_req);
    push(@put_res, $put_req->gen_response(201));
    $leave_now = 0;
  }

  # Leave now if there are no valid requests.  @put_req contains 0's for
  # each invalid URL.
  return @put_res if $leave_now;

  _init_ua unless $ua;

  # For each valid PUT request, create the connection.
  my @put_connections = ();
  my $i = 0;
  foreach my $put_req (@put_req) {
    my $conn;
    if ($put_req) {
      $conn = WebFS::FileCopy::Put->new($put_req);
      # If the connection cannot be created, then get the response from $@.
      $put_res[$i] = $@ unless $conn;
    }
    push(@put_connections, $conn);
    ++$i;
  }

  # Push the data to each valid connection.  For the CODE reference,
  # call it until it returns undef or ''.
  if (ref($string_or_code) eq 'CODE') {
    my $buffer;
    while (defined($buffer = &$string_or_code) and length($buffer)) {
      foreach my $conn (@put_connections) {
        next unless $conn;
        $conn->print($buffer);
      }
    }
  }
  else {
    foreach my $conn (@put_connections) {
      next unless $conn;
      $conn->print($string_or_code);
    }
  }

  # Close the connection and hold onto the close status.
  $i = 0;
  foreach my $put_conn (@put_connections) {
    if ($put_conn) {
      $put_res[$i] = $put_conn->close;
    }
    ++$i;
  }

  @put_res;
}

sub copy_urls {
  unless (@_ == 2 or @_ == 3) {
    $@ = 'Incorrect number of arguments';
    cluck $@;
    return;
  }

  my ($from_input, $to_input, $base) = @_;

  # Create the arrays holding the to and from locations using either the
  # array references or the single URLs.
  my @from = ref($from_input) eq 'ARRAY' ? @$from_input : ($from_input);
  my @to   = ref($to_input)   eq 'ARRAY' ? @$to_input   : ($to_input);

  # Convert string URLs to URI::URLs.
  @from = map { _fix_url($_, $base) } @from;
  @to   = map { _fix_url($_, $base) } @to;

  # Check the arguments.

  # We ignore empty URLs, but make sure there are some URLs.
  unless (grep($_, @from)) {
    $@ = 'No non-empty GET URLs';
    return;
  }

  unless (grep($_, @to)) {
    $@ = 'No non-empty PUT URLs';
    return;
  }

  # Check that the to destination URLs are either file: or ftp:.
  foreach my $to (@to) {
    # Skip empty requests.
    next unless $to;
    my $scheme = $to->scheme;
    unless ($scheme && ($scheme eq 'ftp' or $scheme eq 'file')) {
      $@ = "Can only copy to file or FTP URLs: $to";
      return;
    }
  }

  # All of the from URLs must be files.
  foreach my $from (@from) {
    if ($from and _is_directory($from)) {
      $@ = "Cannot copy directories: $from";
      return;
    }
  }

  # If any of the destination URLs is a file, then there can only be
  # one source URL.
  foreach my $to (@to) {
    next unless $to;
    if (!_is_directory($to) and grep($_, @from) > 1) {
        $@ = 'Cannot copy many files to one file';
        return;
    }
  }

  _init_ua unless $ua;

  # Set up the transfer between the from and to URLs.
  my @get_res = ();
  foreach my $from (@from) {

    # Put together the initial read request.
    my $get_req = LWP::Request->new('GET' => $from);

    # If the from URL is empty, then generate a missing URL response.
    unless ($from) {
      $get_req->{done_cb} = sub { $_[0]; };
      push(@get_res, $get_req->gen_response(400, 'Missing URL in request'));
      next;
    }

    # Do not generate the put requests if this is an empty from URL.
    my @put_req = ();

    foreach (@to) {
      my $to = $_->clone;
      # If the to URL is a directory, then copy the filename from the
      # from URL to the to URL.
      if (_is_directory($to)) {
        my @from_path = split(/\//, $from->epath);
        $to->epath($to->epath . $from_path[$#from_path]);
      }

      # Put together a put request using the output from a get request.
      push(@put_req, LWP::Request->new('PUT' => $to));
    }
    my $get_res = $ua->_start_transfer_request($get_req, @put_req);
    push(@get_res, $get_res) if $get_res;
  }

  # Loop until all of the data is transfered.
  while (1) {
    my $done = 1;
    foreach my $get_res (@get_res) {
      next unless $get_res->is_success;
      $done &&= exists($get_res->{put_requests});
    }
    last if $done || mainloop->empty;
    mainloop->one_event;
  }

  @get_res;
}

# Print a status summary using the return from copy_urls.
sub _dump {
  my @get_res = @_;
  foreach my $get_res (@get_res) {
    my $url = $get_res->request->url;
    print STDERR "GET from $url ";
    unless ($get_res->is_success) {
      print "FAILED ", $get_res->message, "\n";
      next;
    }

    print STDERR "SUCCEEDED\n";
    foreach my $c (@{$get_res->{put_requests}}) {
      $url = $c->request->url;
      if ($c->is_success) {
        print STDERR "    to $url succeeded\n"
      }
      else {
        print STDERR "    to $url failed: ", $c->message, "\n";
      }
    }
  }
}

sub copy_url {
  unless (@_ == 2 or @_ == 3) {
    $@ = 'Incorrect number of arguments';
    cluck $@;
    return;
  }

  # Convert string URLs to URI::URLs.
  my @urls = map { _fix_url($_) } @_;

  my $from = shift(@urls);
  my $to   = shift(@urls);
  my $base = shift(@urls);

  # Check for valid URLs.
  unless ($from) {
    $@ = 'Missing GET URL';
    return;
  }

  unless ($to) {
    $@ = 'Missing PUT URL';
    return;
  }

  # Run the real copy_urls and get the return value.
  my @ret = copy_urls($from, $to, $base);
  return unless @ret;

  my $get_res = shift(@ret);
  unless ($get_res->is_success) {
    $@ = 'GET ' . $get_res->request->url . ': ' . $get_res->message;
    return 0;
  }
  my @put_res = @{$get_res->{put_requests}};

  # This should never happen.
  unless (@put_res) {
    $@ = 'Found a bug: no returned PUT requests from copy_urls';
    cluck $@;
    return;
  }

  # Check each PUT request.
  foreach my $put_res (@put_res) {
    unless ($put_res->is_success) {
      $@ = 'PUT ' . $put_res->request->url . ': ' . $put_res->message;
      return 0;
    }
  }
  1;
}

sub delete_urls {
  my @urls = @_;

  return () unless @urls;

  _init_ua unless $ua;

  # Go through each URL, create a request, and spool it.
  my @del_req = ();
  my @del_res = ();
  my $i = 0;
  foreach my $url (@urls) {
    $url = _fix_url($url);
    my $del_req = LWP::Request->new('DELETE' => $url);

    # $j is created here to be local to this loop and recorded in each
    # anonymous subroutine created below.
    my $j = $i;

    $del_res[$j] = undef;
    $del_req->{done_cb} = sub { $del_res[$j] = shift; };
    $ua->spool($del_req);
    $del_req[$j] = $del_req;
    ++$i;
  }

  # Perform one_event until all of the done requests are handled.
  while (1) {
    my $done = 1;
    foreach my $del_res (@del_res) {
      unless (defined($del_res)) {
        $done = 0;
        last;
      }
    }
    last if $done || mainloop->empty;
    mainloop->one_event;
  }

  # Return the status.
  @del_res;
}

sub move_url {
  unless (@_ == 2 or @_ == 3) {
    $@ = 'Incorrect number of arguments';
    cluck $@;
    return;
  }

  my $from = shift;
  my $to   = shift;
  my $base = shift;

  # Convert string URLs to URI::URLs.
  $from = _fix_url($from, $base);
  $to   = _fix_url($to,   $base);

  # Copy the URL.  Make sure to pass down $@ failures from copy_url.
  if (copy_url($from, $to)) {
    my @ret = delete_urls($from);
    my $ret = $ret[0];
    if ($ret->is_success) {
      return 1;
    }
    else {
      $@ = $ret->message;
      return 0;
    }
  }
  else {
    return 0;
  }
}

sub _list_file_url {
  my $url = shift;

  # Check that the host is ok.
  my $host = $url->host;
  if ($host and $host !~ /^localhost$/i) {
    $@ = 'Only file://localhost/ allowed';
    return;
  }

  # Get file path.
  my $path = $url->local_path;

  # Check that the directory exists and is readable.
  unless (-e $path) {
    $@ = "File or directory `$path' does not exist";
    return;
  }
  unless (-r _) {
    $@ = "User does not have read permission for `$path'";
    return;
  }
  unless (-d _) {
    $@ = "Path `$path' is not a directory";
    return;
  }

  # List the directory.
  unless (opendir(D, $path)) {
    $@ = "Cannot read directory `$path': $!";
    return;
  }

  my @listing = sort readdir(D);

  closedir(D) or warn "Error in closing directory `$path': $!\n";

  @listing;
}

sub _list_ftp_url {
  my $url = shift;

  my $req = LWP::Request->new('GET' => $url);
  $req->{done_cb} = sub { $_[0] };
  my $ftp = _open_ftp_connection($req);
  unless ($ftp) {
    $@ = $@->message;
    return;
  }

  # Get and fix path.
  my @path = $url->path_components;
  # There will always be an empty first component.
  shift(@path);
  # Remove the empty trailing components.
  pop(@path) while @path && $path[-1] eq '';

  # Change directories.
  foreach my $dir (@path) {
    unless ($ftp->cwd($dir)) {
      $@ = "Cannot chdir to `$dir'";
      return;
    }
  }

  # Now get a listing.
  my @listing = $ftp->ls;

  # Close the connection.
  $ftp->quit;

  @listing;
}

sub list_url {
  my $url = shift;

  $url = _fix_url($url);
  unless ($url) {
    $@ = "Missing URL";
    return;
  }

  my $scheme = $url->scheme;
  unless ($scheme) {
    $@ = "Missing scheme in URL $url";
    return;
  }

  my @listing = ();
  if ($scheme eq 'file' || $scheme eq 'ftp' ) {
    my $code = "_list_${scheme}_url";
    no strict 'refs';
    my @listing = &$code($url);
    if (@listing) {
      return @listing;
    }
    else {
      return;
    }
  }
  else {
    $@ = "Unsupported scheme $scheme in URL $url";
    return;
  }

  @listing;
}

# Open a FTP connection.  Return either a Net::FTP object or undef if
# failes.  If somethings fails, then $@ will hold a HTTP::Response
# object.
sub _open_ftp_connection {
  my $req = shift;

  my $url = $req->url;
  unless ($url->scheme eq 'ftp') {
    cluck "Use a FTP URL";
    $@ = $req->gen_response(400, "Use a FTP URL");
    return;
  }

  # Handle user authentication.
  my ($user, $pass) = $req->authorization_basic;
  $user  ||= $url->user || 'anonymous';
  $pass  ||= $url->password || 'nobody@';
  my $acct = $req->header('Account') || 'home';

  # Open the initial connection.
  my $ftp = Net::FTP->new($url->host);
  unless ($ftp) {
    $@ =~ s/^Net::FTP: //;
    $@ = $req->gen_response(500, $@);
    return;
  }

  # Try to log in.
  unless ($ftp->login($user, $pass, $acct)) {
    # Unauthorized access.  Fake a RC_UNAUTHORIZED response.
    $@ = $req->gen_response(401, $ftp->message);
    $@->header("WWW-Authenticate", qq(Basic Realm="FTP login"));
    return;
  }

  # Switch to ASCII or binary mode.
  my $params = $url->params;
  if (defined($params) && $params eq 'type=a') {
    $ftp->ascii;
  } else {
    $ftp->binary;
  }

  $ftp;
}

1;

__END__

=pod

=head1 NAME

WebFS::FileCopy - Get, put, move, copy, and delete files located by URLs

=head1 SYNOPSIS

 use WebFS::FileCopy;

 my @res = get_urls('ftp://www.perl.com', 'http://www.netscape.com');
 print $res[0]->content if $res[0]->is_success;

 put_urls('put this text', 'ftp://ftp/incoming/new', 'file:/tmp/NEW');
 move_url('file:/tmp/NEW', 'ftp://ftp/incoming/NEW.1');
 delete_urls('ftp://ftp/incoming/NEW.1', 'file:/tmp/NEW');

 copy_url('http://www.perl.com/index.html', 'ftp://ftp.host/outgoing/SIG');

 copy_urls(['file:/tmp/file1', 'http://www.perl.com/index.html],
           ['file:/tmp/DIR1/', 'file:/tmp/DIR2', 'ftp://ftp/incoming/']);

 my @list1 = list_url('file:/tmp');
 my @list2 = list_url('ftp://ftp/outgoing/');

=head1 DESCRIPTION

This package provides some simple routines to read, move, copy,
and delete files as references by URLs.

The distinction between files and directories in a URL is tested by
looking for a trailing / in the path.  If a trailing / exists, then
the URL is considered to point to a directory, otherwise it is a
file.

All of the following subroutines are exported to the users namespace
automatically.  If you do not want this, then I<require> this
package instead of I<use>ing it.

=head1 SUBROUTINES

=over 4

=item B<get_urls> I<url> [I<url> [I<url> ...]]

The I<get_urls> function will fetch the documents identified by the given
URLs and returns a list of I<HTTP::Response>s.  You can test if the GET
succeeded by using the I<HTTP::Response> I<is_success> method.  If
I<is_success> returns 1, then use the I<content> method to get the
contents of the GET.  

Geturls performs the GETs in parallel to speed execution and should be
faster than performing individual gets.

Example printing the success and the content from each URL:

    my @urls = ('http://perl.com/', 'file:/home/me/.sig');
    my @response = get_urls(@urls);
    foreach my $res (@response) {
      print "FOR URL ", $res->request->url;
      if ($res->is_success) {
        print "SUCCESS.  CONTENT IS\n", $res->content, "\n";
      }
      else {
        print "FAILED BECAUSE ", $res->message, "\n";
      }
    }

=item B<put_urls> I<string> I<url> [I<url> [I<url> ...]]

=item B<put_urls> I<coderef> I<url> [I<url> [I<url> ...]]

Put the contents of I<string> or the return from &I<coderef>() into the
listed I<url>s.  The destination I<url>s must be either ftp: or file:
and must specify a complete file; no directories are allowed.  If the
first form is used with I<string> then the contents of I<string> will
be sent.  If the second form is used, then I<coderef> is a reference to
a subroutine or anonymous CODE and &I<coderef>() will be called
repeatedly until it returns '' or undef and all of the text it returns
will be stored in the I<url>s.

Upon return, I<put_urls> returns an array, where each element contains
a I<HTTP::Response> object corresponding to the success or failure of
transferring the data to the i-th I<url>.  This object can be tested
for the success or failure of the PUT by using the I<is_success> method
on the element.  If the PUT was not successful, then the I<message>
method may be used to gather an error message explaining why the PUT
failed.  If there is invalid input to I<put_urls> then I<put_urls>
returns an empty list in a list context, an undefined value in a scalar
context, or nothing in a void context, and $@ contains a message
containing explaining the invalid input.

For example, the following code, prints either YES or NO and a failure
message if the put failed.

    @a = put_urls('text',
                  'http://www.perl.com/test.html',
                  'file://some.other.host/test',
                  'ftp://ftp.gps.caltech.edu/test');
    foreach $put_res (@a) {
      print $put_res->request->url, ' ';
      if ($put_res->is_success) {
        print "YES\n";
      }
      else {
        print "NO ", $put_res->message, "\n";
      }
    }

=item B<copy_url> I<url_from> I<url_to> [I<base>]

Copy the content contained in the URL I<url_from> to the location specified
by the URL I<url_to>.  I<url_from> must contain the complete path to a file;
no directories are allowed.  I<url_to> must be a file: or ftp: URL and may
either be a directory or a file.

If supplied, I<base> may be used to convert I<url_from> and I<rurl_to>
from relative URLs to absolute URLs.

On return, I<copy_url> returns 1 on success, 0 on otherwise.  On failure
$@ contains a message explaining the failure.  See L<copy_urls> if you
want to quickly copy a single file to multiple places or copy multiple
files to one directory or both.  L<copy_urls> provides simultaneous file
transfers and will do the task much faster than calling I<copy_url>
many times over.  If invalid input is given to I<copy_url>, then it
returns an empty list in a list context, an undefined value in a scalar
context, or nothing in a void context and $@ contains a message
explaining the invalid input.

=item B<copy_urls> I<url_file_from> I<url_file_to> [I<base>]

=item B<copy_urls> I<url_file_from> I<url_dir_to> [I<base>]

Copy the content contained at the specified URLs to other locations also
specified by URLs.  The first argument to I<copy_urls> is either a single
URL or a reference to an array of URLs to copy.  All of these URLs must
contain the complete path to a file; no directories are allowed.  The
second argument may be a single URL or a reference to an array of URLS.
If any of the destination URLs are a location of a file and not a
directory, then only one URL can be passed as the first argument.  If
a reference to an array of URLs is passed as the second argument, then
all URLs must point to directories, not files.  Only file: and ftp: URLs
may be used as the destination of the copy.

If supplied, I<base> may be used to convert relative URLs to absolute URLs
for all URLs supplied to I<copy_urls>.

The copy operations of the multiple URLs are done in parallel to speed
execution.

On return I<copy_urls> returns a list of the I<LWP::Response> from each
GET performed on the from URLs.  If there is invalid input to I<copy_urls>
then I<copy_urls> returns an empty list in a list context, an undefined
value in a scalar context, or nothing in a void context and contains $@
a message explaining the error.  The success or failure of each GET may
be tested by using I<is_success> method on each element of the list.  If
the GET succeeded (I<is_success> returns TRUE), then hash element
I<'put_requests'> exists and is a reference to a list of
I<LWP::Response>s containing the response to the PUT.  For example, the
following code prints a message containing the results from I<copy_urls>:

    my @get_res = copy_urls(......);
    foreach my $get_res (@get_res) {
      my $url = $get_res->request->url;
      print "GET from $url ";
      unless ($get_res->is_success) {
        print "FAILED\n";
        next;
      }
  
      print "SUCCEEDED\n";
      foreach my $c (@{$get_res->{put_requests}}) {
        $url = $c->request->url;
        if ($c->is_success) {
          print "    to $url succeeded\n"
        }
        else {
          print "    to $url failed: ", $c->message, "\n";
        }
      }
    }

=item B<delete_urls> I<url> [I<url> [I<url> ...]]

Delete the files located by the I<url>s and return a I<HTTP::Response>
for each I<url>.  If the I<url> was successfully deleted, then the 
I<is_success> method returns 1, otherwise it returns 0 and the I<message>
method contains the reason for the failure.

=item B<move_url> I<from> I<to> [I<base>]

Move the contents of the I<from> URL to the I<to> URL.  If I<base> is
supplied, then the I<from> and I<to> URLs are converted from relative
URLs to absolute URLs using I<base>.  If the move was successful, then
I<move_url> returns 1, otherwise it returns 0 and $@ contains a message
explaining why the move failed.  If invalid input was given to I<move_url>
then it returns an empty list in a list context, an undefined value in
a scalar context, or nothing in a void context and $@ contains a message
explaining the invalid input.

=item B<list_url> I<url>

Return a list containing the filenames in the directory located at I<url>.
Only file and FTP directory URLs currently work.  If for any reason the
list can not be obtained, then I<list_url> returns an empty list in a list
context, an undefined value in a scalar context, or nothing in a void
context and $@ contains a message why I<list_url> failed.

=back 4

=head1 SEE ALSO

See also the L<HTTP::Response>, L<HTTP::Request>, and L<LWP::Simple>
manual pages.

=head1 AUTHOR

Blair Zajac <blair@gps.caltech.edu>

=head1 COPYRIGHT

Copyright (c) 1998 Blair Zajac. All rights reserved.  This package is
free software; you can redistribute it and/or modify it under the same
terms as Perl itself.

=cut
