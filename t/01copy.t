# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

use strict;
use vars qw($loaded);

BEGIN { $| = 1; print "1..127\n"; }
END   { print "not ok 1\n" unless $loaded; }

my $ok_count = 1;
sub ok {
  shift or print "not ";
  print "ok $ok_count\n";
  ++$ok_count;
}

use WebFS::FileCopy;
use Cwd;

if (1) {
#  $LWP::UA::DEBUG = 10;
#  $LWP::EventLoop::DEBUG = 10;
#  $LWP::Server::DEBUG = 10;
#  $LWP::Conn::FTP::DEBUG = 10;
#  $LWP::Conn::HTTP::DEBUG = 10;
#  $LWP::Conn::_Connect::DEBUG = 10;
#  $LWP::StdSched::DEBUG = 10;
}

# If we got here, then the package being tested was loaded.
$loaded = 1;
ok(1);									#  1

# Cd to the test directory.
chdir 't' if -d 't';

# Check the _is_directory subroutine.
ok(  WebFS::FileCopy::_is_directory('http://www.gps.caltech.edu') );	#  2
ok( !WebFS::FileCopy::_is_directory('http://www/fff') );		#  3
ok(  WebFS::FileCopy::_is_directory('http://www.gps.caltech.edu/~blair/') );# 4
ok( !WebFS::FileCopy::_is_directory(URI::URL->newlocal('file1')) );	#  5

# Check illegal argument passing to copy_urls.

# Cannot copy more than one file to a single destination file.
ok( !defined copy_urls(['file:/a', 'file:/b'], 'file:/c') );		#  6
ok( $@ eq 'Cannot copy many files to one file' );			#  7

# Cannot copy a directory.
ok( !defined copy_urls('file:/tmp/', 'file:/tmp/') );			#  8
ok( $@ eq 'Cannot copy directories: file:/tmp/' );			#  9

# Cannot copy to non ftp: or file:
ok( !copy_url('http://www.gps.caltech.edu/', 'http://ftp/') );		# 10
ok( $@ eq 'Can only copy to file or FTP URLs: http://ftp/' );		# 11

# Put together file URLs for the test files.  Files 1, 2, and 3, 5 exists and
# file 4 doesn't.
my $cwd = cwd;
my @from_files = qw(file1 file2 file3 file4 file5);
my @from_urls = map { URI::URL->newlocal($_) } @from_files;
my @to_urls = map { WebFS::FileCopy::_fix_url("$_.new") } @from_urls;

# Clean up any output files from previous testing runs.
unlink(map { $_->local_path } @to_urls);

# Test the get_urls.
my  @a =  get_urls(@from_urls);
ok( @a == @from_files );						# 12

ok(  $a[0]->is_success and length($a[0]->content) == 90 );		# 13
ok(  $a[1]->is_success and length($a[1]->content) == 501 );		# 14
ok(  $a[2]->is_success and length($a[2]->content) == 365 );		# 15
ok( !$a[3]->is_success );						# 16
ok(  $a[4]->is_success and length($a[4]->content) == 11683 );		# 17

# Try to put the files.
my $content = $a[4]->content;
my @b = put_urls($content, @to_urls, 'file:/this/path/should/not/exist');
ok(  @b == @from_files+1 );						# 18
ok(  $b[0]->is_success );						# 19
ok(  $b[1]->is_success );						# 20
ok(  $b[2]->is_success );						# 21
ok(  $b[3]->is_success );						# 22
ok(  $b[4]->is_success );						# 23
ok( !$b[5]->is_success );						# 24
ok(  $b[5]->message eq "No such file or directory" );			# 25

# Try to get the same files we just put.
my @c = get_urls(@to_urls);
#print Data::Dumper::Dumper(@c);
ok( @c == @from_files );						# 26
ok( $a[4]->content eq $c[0]->content );					# 27
ok( $a[4]->content eq $c[1]->content );					# 28
ok( $a[4]->content eq $c[2]->content );					# 29
ok( $a[4]->content eq $c[3]->content );					# 30
ok( $a[4]->content eq $c[4]->content );					# 31

# Test the subroutine form of put_urls.
my $i = 0;
my $put_string = $a[2]->content;
sub put_test {
  return undef if $i == length($put_string);
  substr($put_string, $i++, 1);
}

@b = put_urls(\&put_test, 'file:/this/path/should/not/exist', @to_urls);
ok( @b == @from_files+1 );						# 32
ok( !$b[0]->is_success );						# 33
ok(  $b[0]->message eq "No such file or directory" );			# 34
ok(  $b[1]->is_success );						# 35
ok(  $b[2]->is_success );						# 36
ok(  $b[3]->is_success );						# 37
ok(  $b[4]->is_success );						# 38
ok(  $b[5]->is_success );						# 39

# Try to get the same files we just put.
@b = get_urls(@to_urls);
ok( @b == @from_files );						# 40
ok( $a[2]->content eq $b[0]->content );					# 41
ok( $a[2]->content eq $b[1]->content );					# 42
ok( $a[2]->content eq $b[2]->content );					# 43
ok( $a[2]->content eq $b[3]->content );					# 44
ok( $a[2]->content eq $b[4]->content );					# 45

# Try to get many different failures from put_urls.
@b = put_urls('text',
	'http://www.perl.com/test.html',
	'file://some.other.host/test',
	'ftp://ftp.gps.caltech.edu/test',
        '');
ok( !$b[0]->is_success );						# 46
ok(  $b[0]->message eq 'Invalid scheme http' );				# 47
ok( !$b[1]->is_success );						# 48
ok(  $b[1]->message eq "Only file://localhost/ allowed" );		# 49
ok( !$b[2]->is_success );						# 50
ok(  $b[2]->message eq "FTP return code 553" );				# 51
ok( !$b[3]->is_success );						# 52
ok(  $b[3]->message eq "Missing URL in request" );			# 53

# Try to delete some nonexistent files.
@b = delete_urls(
	'http://www.perl.com/test.html',
	'file://some.other.host/test',
	'ftp://ftp.gps.caltech.edu/test',
        '');
ok( !$b[0]->is_success );						# 54
ok(  $b[0]->message eq "File Not Found" );				# 55
ok( !$b[1]->is_success );						# 56
ok(  $b[1]->message eq "Use ftp instead" );				# 57
ok( !$b[2]->is_success );						# 58
ok(  $b[2]->message eq "/test: Permission denied. (Delete)" );		# 59
use Data::Dumper;
#print STDERR Dumper($b[2]), "\n";
#print STDERR $b[2]->message, "\n";
ok( !$b[3]->is_success );						# 60
ok(  $b[3]->message eq "Missing URL in request" );			# 61

# Try to delete the files we created.
@b = delete_urls(@to_urls);
ok( $b[0]->is_success );						# 62
ok( $b[1]->is_success );						# 63
ok( $b[2]->is_success );						# 64
ok( $b[3]->is_success );						# 65
ok( $b[4]->is_success );						# 66

# Try to delete the files again.  This time it should fail.
@b = delete_urls(@to_urls);
ok( !$b[0]->is_success );						# 67
ok( !$b[1]->is_success );						# 68
ok( !$b[2]->is_success );						# 69
ok( !$b[3]->is_success );						# 70
ok( !$b[4]->is_success );						# 71

# Create one file and try to move it.
ok( copy_url($from_urls[4], $to_urls[4]) );				# 72
ok( move_url($to_urls[4], $to_urls[0]) );				# 73

# Now try failures of move_url.
ok( !move_url($to_urls[4], $to_urls[0]) );				# 74
ok( $@ =~ m?/t/file5.new: No such file or directory? );			# 75
ok( !move_url($to_urls[0], 'file://some.other.host/test') );		# 76
ok( $@ eq 'PUT file://some.other.host/test: Only file://localhost/ allowed' ); # 76

# Make sure that if empty URLs are passed, we get the proper return message.
ok( !copy_url(' ', ' ') );						# 78
ok( $@ eq 'Missing GET URL' );						# 79
ok( !copy_url('http://www.perl.com/', ' ') );				# 80
ok( $@ eq 'Missing PUT URL' );						# 81

ok( !copy_urls([], []) );						# 82
ok( $@ eq 'No non-empty GET URLs' );					# 83
ok( !copy_urls('http://www.perl.com/', []) );				# 84
ok( $@ eq 'No non-empty PUT URLs' );					# 85

@b = delete_urls(' ');
ok( !$b[0]->is_success );						# 86
ok(  $b[0]->message eq 'Missing URL in request' );			# 87

@b = get_urls(' ');
ok( !$b[0]->is_success );						# 88
ok(  $b[0]->message eq 'Missing URL in request' );			# 89

@b = move_url(' ', 'file:/tmp/ ');
ok( !$b[0] );								# 90
ok(  $@ eq 'Missing GET URL');						# 91

@b = move_url('/etc/passwd', ' ');
ok( !$b[0] );								# 92
ok(  $@ eq 'Missing PUT URL' );						# 93

@b = put_urls('test', ' ');
ok( !$b[0]->is_success );						# 94
ok(  $b[0]->message eq 'Missing URL in request' );			# 95

# Test copy_urls.
@b = copy_urls(['', $from_urls[0]], [@to_urls, '', 'file:/no/such/path/ZZZ/']);
ok( @b );								# 96
ok( !$b[0]->is_success );						# 97
ok(  $b[0]->message eq 'Missing URL in request' );			# 98
ok(  $b[1]->is_success );						# 99
ok(  $b[1]->{put_requests}[0]->is_success );				# 100
ok(  $b[1]->{put_requests}[1]->is_success );				# 101
ok(  $b[1]->{put_requests}[2]->is_success );				# 102
ok(  $b[1]->{put_requests}[3]->is_success );				# 103
ok(  $b[1]->{put_requests}[4]->is_success );				# 104
ok( !$b[1]->{put_requests}[5]->is_success );				# 105
ok(  $b[1]->{put_requests}[5]->message eq 'Missing URL in request' );	# 106
ok( !$b[1]->{put_requests}[6]->is_success );				# 107
ok(  $b[1]->{put_requests}[6]->message eq 'No such file or directory' ); # 108

# Try to read all of the files we put and compare with what we've read.
@b = get_urls(@to_urls);
ok(  @b == @from_files );						# 109
ok(  $b[0]->is_success and $b[0]->content eq $a[0]->content );		# 110
ok(  $b[1]->is_success and $b[1]->content eq $a[0]->content );		# 111
ok(  $b[2]->is_success and $b[2]->content eq $a[0]->content );		# 112
ok(  $b[3]->is_success and $b[3]->content eq $a[0]->content );		# 113
ok(  $b[4]->is_success and $b[4]->content eq $a[0]->content );		# 114

# Check the directory listing code.
ok( !list_url );							# 115
ok( !list_url('http://www.perl.com/') );				# 116
ok( $@ eq 'Unsupported scheme http in URL http://www.perl.com/' );	# 117
@b = list_url("file://localhost/$cwd");
ok( @b == 12 );								# 118
ok( !list_url('file://localhost/this/path/should/not/exist') );		# 119
# This case insensitive match is done to match on both Unix and Windows.
 #          File or directory `/this/path/should/not/exist' does not exist
ok( $@ =~ m:File or directory `.this.path.should.not.exist' does not exist:i ); # 120
ok( !list_url($from_urls[0]) );						# 121
ok( $@ =~ m:t.file1' is not a directory:i );				# 122
ok( !list_url('ftp://ftp.gps.caltech.edu/ZZZZ') );			# 123
ok( $@ = "Cannot chdir to `ZZZ'" );					# 124
@b = list_url("ftp://ftp.gps.caltech.edu/");
ok( @b == 8 );								# 125

# Clean up the output files.
ok( unlink(map { $_->local_path } @to_urls) == @from_files );		# 126
@b = list_url("file://localhost/$cwd");
ok( @b == 7 );								# 127
