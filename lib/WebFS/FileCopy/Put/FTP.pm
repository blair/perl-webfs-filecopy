package WebFS::FileCopy::Put::FTP;

require 5.004_04;

use strict;
use Exporter;
use Carp qw(cluck);
use Net::FTP;

use vars qw($VERSION @ISA);

$VERSION = do {my @r=(q$Revision: 1.00 $=~/\d+/g);sprintf "%d."."%02d"x$#r,@r};
@ISA     = qw(Exporter);

sub new {
  my $class = shift;
  my $req   = shift;

  my $ftp = WebFS::FileCopy::_open_ftp_connection($req) or return;

  # Get and fix path.
  my $url = $req->url;
  my @path = $url->path_segments;
  # There will always be an empty first component.
  shift(@path);
  # Remove the empty trailing components.
  pop(@path) while @path && $path[-1] eq '';
  my $remote_file = pop(@path);
  unless ($remote_file) {
    $@ = $req->give_response(500, "No remote file specified");
    return;
  }

  # Change directories.
  foreach my $dir (@path) {
    unless ($ftp->cwd($dir)) {
      $@ = $req->give_response(404, "Cannot chdir to `$dir'");
      return;
    }
  }

  my $data = $ftp->stor($url->path);
  unless ($data) {
    $@ = $req->give_response(400, "FTP return code " . $ftp->code);
    $@->content_type('text/plain');
    $@->content($ftp->message);
    return;
  }

  bless {'req' => $req, 'ftp' => $ftp, 'data' => $data}, $class;  
}

sub print {
  my $self = shift;
  my $buffer = shift;

  return unless defined($buffer);

  $self->{data}->write($buffer, length($buffer));
}

sub close {
  my $self = shift;

  my $ret = $self->{data}->close;
  $self->{ftp}->quit;
  $self->{req}->give_response($ret ? 201 : 500);
}

1;
