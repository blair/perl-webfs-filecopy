package WebFS::FileCopy::Put::File;

require 5.004_04;

use strict;
use Exporter;
use Carp qw(cluck);

use vars qw($VERSION @ISA);

$VERSION = do {my @r=(q$Revision: 1.00 $=~/\d+/g);sprintf "%d."."%02d"x$#r,@r};
@ISA     = qw(Exporter);

sub new {
  my $class = shift;
  my $req   = shift;

  my $url   = $req->url;

  my $scheme = $url->scheme;
  unless ($scheme eq 'file') {
    $@ = $req->give_response(500,
			     "WebFS::FileCopy::Put::File invalid scheme $scheme");
    return;
  }

  my $host = $url->host;
  if ($host and $host !~ /^localhost$/i) {
    $@ = $req->give_response(400, 'Only file://localhost/ allowed');
    return;
  }

  # Open the file.
  local *FH;
  open(FH, '>' . $url->file) or do {
    $@ = $req->give_response(401, "$!");
    return;
  };

  my $self = bless {'req' => $req, 'handle' => *FH}, $class;
  $self;
}

sub print {
  my $self   = shift;
  my $buffer = shift;

  return unless defined($buffer);

  print {$self->{handle}} $buffer;
}

sub close {
  my $self = shift;

  my $ret = close($self->{handle});
  $self->{req}->give_response($ret ? 201 : 500);
}

1;
