# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

use strict;
use vars qw($loaded);

BEGIN { $| = 1; print "1..126\n"; }
END   { print "not ok 1\n" unless $loaded; }

my $ok_count = 1;
sub ok {
  shift or print "not ";
  print "ok $ok_count\n";
  ++$ok_count;
}

use WebFS::FileCopy;
use Cwd;

# If we got here, then the package being tested was loaded.
$loaded = 1;
ok(1);

# Cd to the test directory.
chdir 't' if -d 't';

# Check the _is_directory subroutine.
ok(  WebFS::FileCopy::_is_directory('http://www.gps.caltech.edu') );	# 2
ok( !WebFS::FileCopy::_is_directory('http://www/fff') );		# 3
ok(  WebFS::FileCopy::_is_directory('http://www.gps.caltech.edu/~blair/') );# 4

# Check illegal argument passing to copy_urls.

# Cannot copy more than one file to a single destination file.
ok( !defined copy_urls(['file:/a', 'file:/b'], 'file:/c') );		# 5
ok( $@ eq 'Cannot copy many files to one file' ); # 6

# Cannot copy a directory.
ok( !defined copy_urls('file:/tmp/', 'file:/tmp/') );			# 7
ok( $@ eq 'Cannot copy directories: file:/tmp/' );			# 8

# Cannot copy to non ftp: or file:
ok( !copy_url('http://www.gps.caltech.edu/', 'http://ftp/') );		# 9
ok( $@ eq 'Can only copy to file or FTP URLs: http://ftp/' );		# 10

# Put together file URLs for the test files.  Files 1, 2, and 3, 5 exists and
# file 4 doesn't.
my $cwd = cwd;
my @from_files = qw(file1 file2 file3 file4 file5);
my @from_urls = map { "file://localhost$cwd/$_" } @from_files;

# Test the get_urls.
my @a = get_urls(@from_urls);
ok( @a == @from_files );						# 11
ok(  $a[0]->is_success and length($a[0]->content) == 90 );		# 12
ok(  $a[1]->is_success and length($a[1]->content) == 501 );		# 13
ok(  $a[2]->is_success and length($a[2]->content) == 365 );		# 14
ok( !$a[3]->is_success );						# 15
ok(  $a[4]->is_success and length($a[4]->content) == 11683 );		# 16

# Try to put the files.
my @to_urls = map { WebFS::FileCopy::_fix_url("$_.new") } @from_urls;
my $content = $a[4]->content;
my @b = put_urls($content, @to_urls, 'file:/this/path/should/not/exist');
ok(  @b == @from_files+1 );						# 17
ok(  $b[0]->is_success );						# 18
ok(  $b[1]->is_success );						# 19
ok(  $b[2]->is_success );						# 20
ok(  $b[3]->is_success );						# 21
ok(  $b[4]->is_success );						# 22
ok( !$b[5]->is_success );						# 23
ok(  $b[5]->message eq "No such file or directory" );			# 24

# Try to get the same files we just put.
my @c = get_urls(@to_urls);
#print Data::Dumper::Dumper(@c);
ok( @c == @from_files );						# 25
ok( $a[4]->content eq $c[0]->content );					# 26
ok( $a[4]->content eq $c[1]->content );					# 27
ok( $a[4]->content eq $c[2]->content );					# 28
ok( $a[4]->content eq $c[3]->content );					# 29
ok( $a[4]->content eq $c[4]->content );					# 30

# Test the subroutine form of put_urls.
my $i = 0;
my $put_string = $a[2]->content;
sub put_test {
  return undef if $i == length($put_string);
  substr($put_string, $i++, 1);
}

@b = put_urls(\&put_test, 'file:/this/path/should/not/exist', @to_urls);
ok( @b == @from_files+1 );						# 31
ok( !$b[0]->is_success );						# 32
ok(  $b[0]->message eq "No such file or directory" );			# 33
ok(  $b[1]->is_success );						# 34
ok(  $b[2]->is_success );						# 35
ok(  $b[3]->is_success );						# 36
ok(  $b[4]->is_success );						# 37
ok(  $b[5]->is_success );						# 38

# Try to get the same files we just put.
@b = get_urls(@to_urls);
ok( @b == @from_files );						# 39
ok( $a[2]->content eq $b[0]->content );					# 40
ok( $a[2]->content eq $b[1]->content );					# 41
ok( $a[2]->content eq $b[2]->content );					# 42
ok( $a[2]->content eq $b[3]->content );					# 43
ok( $a[2]->content eq $b[4]->content );					# 44

# Try to get many different failures from put_urls.
@b = put_urls('text',
	'http://www.perl.com/test.html',
	'file://some.other.host/test',
	'ftp://ftp.gps.caltech.edu/test',
        '');
ok( !$b[0]->is_success );						# 45
ok(  $b[0]->message eq 'Invalid scheme http' );				# 46
ok( !$b[1]->is_success );						# 47
ok(  $b[1]->message eq "Only file://localhost/ allowed" );		# 48
ok( !$b[2]->is_success );						# 49
ok(  $b[2]->message eq "FTP return code 553" );				# 50
ok( !$b[3]->is_success );						# 51
ok(  $b[3]->message eq "Missing URL in request" );			# 52

# Try to delete some nonexistent files.
@b = delete_urls(
	'http://www.perl.com/test.html',
	'file://some.other.host/test',
	'ftp://ftp.gps.caltech.edu/test',
        '');
ok( !$b[0]->is_success );						# 53
ok(  $b[0]->message eq "File Not Found" );				# 54
ok( !$b[1]->is_success );						# 55
ok(  $b[1]->message eq "Use ftp instead" );				# 56
ok( !$b[2]->is_success );						# 57
ok(  $b[2]->message eq "/test: Permission denied. (Delete)" );		# 58
ok( !$b[3]->is_success );						# 59
ok(  $b[3]->message eq "Missing URL in request" );			# 60

# Try to delete the files we created.
@b = delete_urls(@to_urls);
ok( $b[0]->is_success );						# 61
ok( $b[1]->is_success );						# 62
ok( $b[2]->is_success );						# 63
ok( $b[3]->is_success );						# 64
ok( $b[4]->is_success );						# 65

# Try to delete the files again.  This time it should fail.
@b = delete_urls(@to_urls);
ok( !$b[0]->is_success );						# 66
ok( !$b[1]->is_success );						# 67
ok( !$b[2]->is_success );						# 68
ok( !$b[3]->is_success );						# 69
ok( !$b[4]->is_success );						# 70

# Create one file and try to move it.
ok( copy_url($from_urls[4], $to_urls[4]) );				# 71
ok( move_url($to_urls[4], $to_urls[0]) );				# 72

# Now try failures of move_url.
ok( !move_url($to_urls[4], $to_urls[0]) );				# 73
ok( $@ =~ m?/t/file5.new: No such file or directory? );			# 74
ok( !move_url($to_urls[0], 'file://some.other.host/test') );		# 75
ok( $@ eq 'PUT file://some.other.host/test: Only file://localhost/ allowed' ); # 76

# Make sure that if empty URLs are passed, we get the proper return message.
ok( !copy_url(' ', ' ') );						# 77
ok( $@ eq 'Missing GET URL' );						# 78
ok( !copy_url('http://www.perl.com/', ' ') );				# 79
ok( $@ eq 'Missing PUT URL' );						# 80

ok( !copy_urls([], []) );						# 81
ok( $@ eq 'No non-empty GET URLs' );					# 82
ok( !copy_urls('http://www.perl.com/', []) );				# 83
ok( $@ eq 'No non-empty PUT URLs' );					# 84

@b = delete_urls(' ');
ok( !$b[0]->is_success );						# 85
ok(  $b[0]->message eq 'Missing URL in request' );			# 86

@b = get_urls(' ');
ok( !$b[0]->is_success );						# 87
ok(  $b[0]->message eq 'Missing URL in request' );			# 88

@b = move_url(' ', 'file:/tmp/ ');
ok( !$b[0] );								# 89
ok(  $@ eq 'Missing GET URL');						# 90

@b = move_url('/etc/passwd', ' ');
ok( !$b[0] );								# 91
ok(  $@ eq 'Missing PUT URL' );						# 92

@b = put_urls('test', ' ');
ok( !$b[0]->is_success );						# 93
ok(  $b[0]->message eq 'Missing URL in request' );			# 94

# Test copy_urls.
@b = copy_urls(['', $from_urls[0]], [@to_urls, '', 'file:/no/such/path/ZZZ/']);
ok( @b );								# 95
ok( !$b[0]->is_success );						# 96
ok(  $b[0]->message eq 'Missing URL in request' );			# 97
ok(  $b[1]->is_success );						# 98
ok(  $b[1]->{put_requests}[0]->is_success );				# 99
ok(  $b[1]->{put_requests}[1]->is_success );				# 100
ok(  $b[1]->{put_requests}[2]->is_success );				# 101
ok(  $b[1]->{put_requests}[3]->is_success );				# 102
ok(  $b[1]->{put_requests}[4]->is_success );				# 103
ok( !$b[1]->{put_requests}[5]->is_success );				# 104
ok(  $b[1]->{put_requests}[5]->message eq 'Missing URL in request' );	# 105
ok( !$b[1]->{put_requests}[6]->is_success );				# 106
ok(  $b[1]->{put_requests}[6]->message eq 'No such file or directory' ); # 107

# Try to read all of the files we put and compare with what we've read.
@b = get_urls(@to_urls);
ok(  @b == @from_files );						# 108
ok(  $b[0]->is_success and $b[0]->content eq $a[0]->content );		# 109
ok(  $b[1]->is_success and $b[1]->content eq $a[0]->content );		# 110
ok(  $b[2]->is_success and $b[2]->content eq $a[0]->content );		# 111
ok(  $b[3]->is_success and $b[3]->content eq $a[0]->content );		# 112
ok(  $b[4]->is_success and $b[4]->content eq $a[0]->content );		# 113

# Check the directory listing code.
ok( !list_url );							# 114
ok( !list_url('http://www.perl.com/') );				# 115
ok( $@ eq 'Unsupported scheme http in URL http://www.perl.com/' );	# 116
@b = list_url("file://localhost/$cwd");
ok( @b == 12 );								# 117
ok( !list_url('file://localhost/this/path/should/not/exist') );		# 118
ok( $@ eq "File or directory `/this/path/should/not/exist' does not exist" ); # 119
ok( !list_url($from_urls[0]) );						# 120
ok( $@ =~ /file1' is not a directory/ );				# 121
ok( !list_url('ftp://ftp.gps.caltech.edu/ZZZZ') );			# 122
ok( $@ = "Cannot chdir to `ZZZ'" );					# 123
@b = list_url("ftp://ftp.gps.caltech.edu/");
ok( @b == 8 );								# 124

# Clean up the output files.
ok( unlink(map { $_->local_path } @to_urls) == @from_files );		# 125
@b = list_url("file://localhost/$cwd");
ok( @b == 7 );								# 126
