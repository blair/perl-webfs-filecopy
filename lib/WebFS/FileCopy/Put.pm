package WebFS::FileCopy::Put; 

require 5.004_04;

use strict;
use Exporter;
require WebFS::FileCopy::Put::File;
require WebFS::FileCopy::Put::FTP;

use vars qw($VERSION @ISA);

$VERSION = do {my @r=(q$Revision: 0.03 $=~/\d+/g);sprintf "%d."."%02d"x$#r,@r};
@ISA     = qw(Exporter); 
 
sub new { 
  my $class = shift;
  my $req   = shift;

  unless (ref($req) eq 'LWP::Request') {
    $@ = LWP::Request->new(400, "WebFS::FileCopy::Put given invalid request");
    return;
  }

  # We put this in so that give_response can be used.
  $req->{done_cb} = sub { $_[0]; };

  # Check that we have a URL.
  my $url = $req->url;
  unless ($url) {
    $@ = $req->give_response(400, 'Missing URL in request');
    return;
  }

  my $scheme = $url->scheme;
  if ($scheme eq 'ftp') {
    WebFS::FileCopy::Put::FTP->new($req);
  } 
  elsif ($scheme eq 'file') {
    WebFS::FileCopy::Put::File->new($req);
  }
  else {
    $@ = $req->give_response(500,
			     "WebFS::FileCopy::Put invalid scheme $scheme");
    return; 
  } 
} 

1;

__END__

=pod

=head1 NAME

WebFS::FileCopy::Put - Object for putting data to either file or ftp URL

=head1 SYNOPSIS

 use WebFS::FileCopy::Put;

 my $req = HTTP::Request->new(PUT => 'file:/tmp/zzz');
 my $put = WebFS::FileCopy::Put->new($req);
 if ($put) {
   $put->print "Content goes here\n";
   my $res = $put->close;
   print $res->as_string, "\n";
 }
 else {
   my $res = $@;
   print $res->message, "\n";
 }

=head1 DESCRIPTION

An WebFS::FileCopy::Put object is used to put data to a remote file on an
FTP server or a local file.  The location is specified by using
a LWP::Request object.

=head1 METHODS

=over 4

The following methods are available:

=item B<new> I<request>

Returns either an I<WebFS::FileCopy::Put::FTP> or
I<WebFS::FileCopy::PUT::File> object if a file or FTP put I<request> is
passed.  If invalid arguments are passed to new or if the put cannot be
created, then undef is returned and $@ will contain a valid I<HTTP::Response>.

=item B<print> I<buffer>

Put the contents of I<buffer> to the PUT file.

=item B<close>

Close the PUT file and return a I<LWP::Response>, which can be used to test
for the success or failure of the close using the I<is_success> method.

=head1 SEE ALSO

See also the L<WebFS::FileCopy> and L<LWP::Simple> manual pages.

=head1 AUTHOR

Blair Zajac <blair@gps.caltech.edu>

=head1 COPYRIGHT

Copyright (c) 1998 by Blair Zajac.  All rights reserved.  This package
is free software; you can redistribute it and/or modify it under the same
terms as Perl itself.

=cut
