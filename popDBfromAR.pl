#!/usr/bin/perl -I/Users/tdall/copyExecs
#
#   tradeManager.pl [yyyy-mm-dd]

#use Getopt::Std;
#use PGPLOT;
#use DBD::SQLite;
use Carp;
use DBI;    # see http://search.cpan.org/perldoc?DBI for how-to
use strict;
$|=1;

require "utils.pl";
#require "pg_utils.pl";
#require "trader_utils.pl";
my ($dbh,$file, $in,$tick,$day, $open, $high, $low, $close, $vol,$dum,$ignore,$skip,@skip);
my $dbfile = "/Users/tdall/geniustrader/traderThomas";

# prepare database file
#
if (-e $dbfile) {
    $dbh = DBI->connect("dbi:SQLite:$dbfile", undef, undef, {
        AutoCommit => 1,
        RaiseError => 1,
        sqlite_see_if_its_a_number => 1,
      });
} else {
    die "no such file: $dbfile\n";
}

# read dates to be skipped
#
open SKIP, "<skipdates4db.save" || die "no skip file...\n";
chomp(@skip = <SKIP>);
close SKIP;

# process each .csv file in the format of ARIVA
foreach $file (@ARGV) {
    print "Processing $file... ";
    # get ticker symbol
    if ($file =~ /wkn_(.*)_hist/) {
        $tick = $1;
        print "ticker = $tick\n"; 
    } else {
        carp "Can't extract ticker from filename of $file\n";
        next;
    }
    $ignore = 0;
    open IN, "<$file" || die "Error opening $file: $!\n";
    DATA:while ($in = <IN>) {
        chomp($in);
        next DATA unless ($in =~ /^\d/);
        $in =~ s/\.//sg;
        $in =~ s/\,/./sg;
        $in =~ s/\s+//sg;
        ($day, $open, $high, $low, $close, $vol, $dum) = split /;/, $in;
        next DATA if ($day =~ /\d{4}-01-01/ || $day =~ /\d{4}-12-25/);
        foreach $skip (@skip) {
            next DATA if ($day eq $skip);
        }
        unless ($open && $high && $low) {
            if ($ignore) {
                $open = 'NULL';
                $high = 'NULL';
                $low = 'NULL';
            } else {
                print "enter $tick 'open high low' for $day (I to ignore rest, N to skip): "; chomp($dum = <STDIN>);
                if ($dum =~ /[iI]/) {
                    $ignore = 1;
                    print "OK, setting remaining empty values to NULL\n";
                    $open = 'NULL';
                    $high = 'NULL';
                    $low = 'NULL';
                } elsif ($dum =~ /[nN]/) {
                    print "... skipping $day\n";
                    next DATA;
                } else {
                    ($open, $high, $low) = split /\s+/, $dum;
                    die "can't compute..." unless ($open && $high && $low);
                }
            }
        }
        #next unless ($open>0 && $high>0 && $low>0 && $close>0);
#        print "'$tick','$day',$open,$high,$low,$close,$vol\n";
        $dbh -> do(qq{INSERT into stockprices (symbol, date, day_open, day_high, day_low, day_close, volume) VALUES('$tick','$day',$open,$high,$low,$close,$vol)});
    }
    close IN;
    print "Done!\n";
}

#        print $in; exit;


# clean up
#
$dbh->disconnect;
