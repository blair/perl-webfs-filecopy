package WebFS::FileCopy::Put::File;

require 5.004_04;

use strict;
use Exporter;
use Carp qw(cluck);

use vars qw(@ISA $VERSION);

@ISA     = qw(Exporter);
$VERSION = do {my @r=(q$Revision: 1.01 $=~/\d+/g);sprintf "%d."."%02d"x$#r,@r};

sub new {
  my ($class, $req) = @_;

  my $uri   = $req->uri;
  my $scheme = $uri->scheme;
  unless ($scheme eq 'file') {
    $@ = $req->give_response(500,
			     "WebFS::FileCopy::Put::File invalid scheme $scheme");
    return;
  }

  my $host = $uri->host;
  if ($host and $host !~ /^localhost$/i) {
    $@ = $req->give_response(400, 'Only file://localhost/ allowed');
    return;
  }

  # Open the file.
  local *FH;
  open(FH, '>' . $uri->file) or do {
    $@ = $req->give_response(401, "$!");
    return;
  };

  my $self = bless {'req' => $req, 'handle' => *FH}, $class;
  $self;
}

sub print {
  return unless defined($_[1]);
  print {$_[0]->{handle}} $_[1];
}

sub close {
  my $self = shift;

  my $ret = close($self->{handle});
  $self->{req}->give_response($ret ? 201 : 500);
}

sub DESTROY {
  if ($WebFS::FileCopy::WARN_DESTROY) {
    my $self = shift;
    print STDERR "DESTROYing $self\n";
  }
}

1;
