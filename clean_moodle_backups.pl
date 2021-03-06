#!/usr/bin/env perl

use warnings;
use DBI;
use Getopt::Long qw(:config gnu_getopt auto_version auto_help no_ignore_case);
use Pod::Usage;

my $message_text  = "Clean Moodle backups files automatically.";
my $exit_status   = 0;          ## The exit status to use
my $filehandle    = \*STDERR;   ## The filehandle to write to
  
#pod2usage({ -message => $message_text,
#            -exitval => $exit_status,  
#            -output  => $filehandle });

my $FILEDIR  = "./";
my $DATABASE = "moodle";
my $DAYSOLD  = 60;
my $PORT     = 3306;
my $SERVER   = "localhost";
my $USER     = "root";
my $PASSWORD;
GetOptions("d|db=s"       => \$DATABASE,
           "f|filedir=s"  => \$FILEDIR,
           "o|daysold=i"  => \$DAYSOLD,
           "p|port=i"     => \$PORT,
           "s|host=s"     => \$SERVER,
           "u|user=s"     => \$USER,
           "w|password=s" => \$PASSWORD);

sub getPathFromHash {
    my $mys = $_[0];
    my $p1 = substr($mys, 0, 2);
    my $p2 = substr($mys, 2, 2);
    return { dir => $p1, subdir => $p2 };
}

sub pathIsEmpty {
    my $some_dir = $_[0];
    opendir(my $dh, $some_dir) || die "Can't open $some_dir"; 
        my @lines = grep(!/^\.{1,2}/, readdir($dh));
        # if $n is 0, then path is empty!
        my $n = scalar(@lines);
    closedir $dh;
    return $n == 0 ? 1 : 0
}

sub main {
    my $user = $USER;
    my $pwd = $PASSWORD;
    my $dsn = "dbi:mysql:$DATABASE:$SERVER:$PORT";
    my $dbc = DBI->connect($dsn, $user, $pwd) || die;
    # time and timemodified are in unix timestamp format - e.g. number of seconds since 1/1/1970 - 
    # so we multiplicate $DAYSOLD by 86400 to get time "$DAYSOLD" ago.
    my $datefrom = time - 86400 * $DAYSOLD;
    my $query = qq(SELECT id, contenthash, timecreated, timemodified 
                   FROM mdl_files 
                   WHERE (filename LIKE 'backup%.zip' OR filename LIKE 'backup%.mbz')
                    AND timemodified <= $datefrom
                   ORDER BY timemodified desc);
    my $sth = $dbc->prepare($query);
    $sth->execute();
    while (my $row = $sth->fetchrow_hashref) {
        my $id = $row->{"id"};
        my $hash = $row->{"contenthash"};
        my $dirs = getPathFromHash($hash);
        my $fulldir = "$FILEDIR/$dirs->{'dir'}";
        my $fullsubdir = "$fulldir/$dirs->{'subdir'}";
        my $fullpath = "$fullsubdir/$hash";
        if (-e $fullpath) {
            my $datetime = localtime();
            print "$datetime : let's remove file $fullpath\n";
            system("rm -f $fullpath");
        }
        for $path (($fullsubdir, $fulldir)) {
            if (-d $path && pathIsEmpty($path)) {
                my $datetime = localtime();
                print "$datetime : let's remove dir $path\n";
                system("rm -rf $path")
            }
        my $delquery = "DELETE FROM mdl_files WHERE id = $id";
        my $delsth = $dbc->prepare($delquery);
        my $datetime = localtime();
        print "$datetime : cleaning database, delete row with id: $id\n";
        $delsth->execute(); 
        }
    }
    $dbc->disconnect;
}

main();

 __END__
