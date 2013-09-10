#!/usr/bin/perl -I/Users/tdall/copyExecs
# give name of file with ticks on the command line ending in .tick OR individual ticker symbols
# fetches the csv files from yahoo finance
#
# checks first to see if the symbol is there. If not then it is created with beancounter first.
# Any existing price data for the symbol will be deleted.
#
# -D : remove all previous values of this stock
# -A : do not use ARIVA data even if present


use DBI;    # see http://search.cpan.org/perldoc?DBI for how-to
use Getopt::Std;
$|=1;
my %opt;
getopts('DA', \%opt);
require "utils.pl";

if ($ARGV[0] =~ /tick/) {
    @ticks = <>;
} else {
    @ticks = ($ARGV[0]);
}
$nt = @ticks;

$dbfile = "/Users/tdall/geniustrader/traderThomas";
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

@date = ();
$it = 0;
foreach $tick (@ticks) {
    chomp($tick);
    @ariva = ();    # reset the ARIVA data

    #### Code: check if exists, if not then create
    @b = @{$dbh->selectcol_arrayref(qq{SELECT symbol FROM stockinfo WHERE symbol='$tick'})};
    unless ($b[0] =~ /$tick/) {
        print "$tick not present, creating...\n";# exit;
        `beancounter --dbsystem SQLite --dbname $dbfile addstock $tick`;
    }
    # read ARIVA data from file!
    if (-e "/Users/tdall/Documents/Business/Trading_business/data/old_from_ARIVA/wkn_${tick}_historic.csv" && ! $opt{'A'}) {
        open AR, "</Users/tdall/Documents/Business/Trading_business/data/old_from_ARIVA/wkn_${tick}_historic.csv" || die "cannot find file, better run again!\n";
        chomp(@ariva = <AR>);
        close AR;
    } else {
        print "NOTE: no ARIVA data will be used!\n";
    }
    $it++;
    $file = $tick . ".csv";
    print "$tick .. $it/$nt ";
    if (-e "$file" && -s "$file") {
        &InsertInDB();
    } else {
        `curl -o $file http://ichart.yahoo.com/table.csv?s=$tick`;
        &InsertInDB();
    }
}
# clean up
#
$dbh->disconnect;
## `beancounter --dbsystem SQLite --dbname $dbfile update`;
print "Done!\n";


sub InsertInDB {
    $ignore = 0;
    open IN, "<$file" || die "Error opening $file: $!\n";
    # first remove the old data... careful!
    # remove all previous entries if it is a full update (-D)
    if ($opt{'D'}) {
        print "Deleting all previous data for $tick...\n";
        $dbh -> do(qq{DELETE FROM stockprices WHERE symbol = '$tick'});
    }
    print "updating database ...";
    DATA:while ($in = <IN>) {
        # first going through the data from yahoo, entering it as is, and if there are conflicts, trying to solve with ARIVA data
        #
        chomp($in);
        next DATA unless ($in =~ /^\d/);
        ($day, $open, $high, $low, $close, $vol, $dum) = split /,/, $in;
        next DATA if ($day =~ /\d{4}-01-01/ || $day =~ /\d{4}-12-25/);
        next DATA if ($vol eq '000');
        foreach $skip (@skip) {
            next DATA if ($day eq $skip);
        }
        @tmp = ();  # reset the tmp-array
        if ($low > $close || $high < $close) {
            if ($ariva[0]) {    # if we're using ARIVA data...
                # take the close price from the ARIVA file in @ariva
                LINE:foreach $line (@ariva) {
                    if ($line =~ /$day/) {
                        print "found $line... ";
                        @tmp = split /;/, $line;        # format = 2013-02-13;12,96;13,12;12,84;12,97;825.402;10.697.060
                        $tmp[4] =~ s/\,/./sg;
                        last LINE;
                    }                    
                }
                if ($low > $tmp[4] || $high < $tmp[4]) {
                    warn "still wrong on $day, found $tmp[4] (before $close) with O,H,L,C = $open, $high, $low, $close...";
                    # check if the low and high are deviating as well
                    $tmp[2] =~ s/\,/./sg;   # high
                    $tmp[3] =~ s/\,/./sg;   # low
                    $close = $tmp[4];   # should anyway be changed...
                    if ($tmp[2] =~ /\d/ && $tmp[3] =~ /\d/) {
                        if ($low > $close) {
                            $low = $tmp[3];
                        }
                        if ($high < $close) {
                            $high = $tmp[2];
                        }
                    }
                    if ($low > $close || $high < $close) {
                        # last check...
                        warn "STILL wrong on $day; read $in, alternative $line... skipping the rest";
                        $ignore = 1;
                        last DATA;
                    }
                } else {
                    $close = $tmp[4];
                }
            } else {    # no ARIVA data, so figure out how to fix this...
                print "WARNING: $day O-H-L-C: $open, $high, $low, $close... Which one to fix [ohlcs]:"; $do = <STDIN>;
                if ($do =~ /[oO]/) {
                    print "Enter O = "; $open = <STDIN>;
                    chomp($open);
                } elsif ($do =~ /[hH]/) {
                    print "Enter H = "; $high = <STDIN>;
                    chomp($high);                
                } elsif ($do =~ /[lL]/) {
                    print "Enter L = "; $low = <STDIN>;
                    chomp($low);                
                } elsif ($do =~ /[cC]/) {
                    print "Enter C = "; $close = <STDIN>;
                    chomp($close);                
                } else {
                    $ignore = 1;
                }
            }
        }
        if ($low > $open || $high < $open) {
            if ($ariva[0]) {    # if we're using ARIVA data...
            # take the close price from the ARIVA file in @ariva
                LINE:foreach $line (@ariva) {
                    if ($line =~ /$day/) {
                        print "found $line... ";
                        @tmp = split /;/, $line;        # format = 2013-02-13;12,96;13,12;12,84;12,97;825.402;10.697.060
                        $tmp[1] =~ s/\,/./sg;
                        last LINE;
                    }                    
                }
                if ($low > $tmp[4] || $high < $tmp[4]) {
                    warn "still wrong on $day, found $tmp[4] (before $open) with O,H,L,C = $open, $high, $low, $close...";
                    # check if the low and high are deviating as well
                    $tmp[2] =~ s/\,/./sg;   # high
                    $tmp[3] =~ s/\,/./sg;   # low
                    $open = $tmp[1];   # should anyway be changed...
                    if ($tmp[2] =~ /\d/ && $tmp[3] =~ /\d/) {
                        if ($low > $open) {
                            $low = $tmp[3];
                        }
                        if ($high < $open) {
                            $high = $tmp[2];
                        }
                    }
                    if ($low > $open || $high < $open) {
                        # last check...
                        warn "STILL wrong on $day; read $in, alternative $line... skipping the rest";
                        $ignore = 1;
                        last DATA;
                    }
                } else {
                    $open = $tmp[1];
                }
            } else {    # no ARIVA data, so figure out how to fix this...
                print "WARNING: $day O-H-L-C: $open, $high, $low, $close... Which one to fix [ohlcs]:"; $do = <STDIN>;
                if ($do =~ /[oO]/) {
                    print "Enter O = "; $open = <STDIN>;
                    chomp($open);
                } elsif ($do =~ /[hH]/) {
                    print "Enter H = "; $high = <STDIN>;
                    chomp($high);                
                } elsif ($do =~ /[lL]/) {
                    print "Enter L = "; $low = <STDIN>;
                    chomp($low);                
                } elsif ($do =~ /[cC]/) {
                    print "Enter C = "; $close = <STDIN>;
                    chomp($close);                
                } else {
                    $ignore = 1;
                }
            }
        }
        # last check...
        @tmp = ($open, $high, $low, $close);
        $tmax = max(@tmp);
        $tmin = min(@tmp);
        if (($tmax == $high && $tmin == $low) || $ignore) { 
            1;
        } else {
            print "  ***$tick*** $day: O-H-L-C =   $open, $high, $low, $close mismatch... (enter 'S' to ignore and skip)\n";
            print "enter corrct numbers space sep: "; $inp = <STDIN>;
            chomp($inp);
            if ($inp =~ /[a-zA-Z]/) {
                $ignore = 1;
            } else {
                ($open, $high, $low, $close) = split /\s+/, $inp;
            }
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
        # update with new data if the date is not already in the db
        @b = $dbh->selectrow_array(qq{SELECT * FROM stockprices WHERE symbol='$tick' AND date='$day'});
        $ntmp = @b;
        if ($ntmp) {
            # something is there, so it's an update not an insert
            # pos 0=symbol, 1=date, 3=open, 4=low, 5=high, 6=close, 10=volume
            if ($b[3]==$open && $b[4]==$low && $b[5]==$high && $b[6]==$close && $b[10]==$vol) {
                # no do nothin...
            } else {
                print "Warn: updating on $day from $b[3],$b[4],$b[5],$b[6],$b[10] -> $open,$low,$high,$close,$vol\n";
                $sth = $dbh->prepare(qq{UPDATE stockprices SET day_open=$open, day_high=$high, day_low=$low, day_close=$close, volume=$vol WHERE symbol='$tick' AND date='$day'});
                $sth -> execute();
            }
        } else {
            $dbh -> do(qq{INSERT into stockprices (symbol, date, day_open, day_high, day_low, day_close, volume) VALUES('$tick','$day',$open,$high,$low,$close,$vol)});
        }
        push @date, $day;
    }
    $dayBeg = $date[-1];    $dayEnd = $date[0];
    close IN;
    foreach $in (@ariva) {
        # now go through ariva data and see if there are any days to add that were left out of the yahoo data...
        chomp($in);
        next unless ($in =~ /^\d/);
        foreach $skip (@skip) {
            next if ($in =~ /$skip/);
        }
        $in =~ s/\.//sg;
        $in =~ s/\,/./sg;
        $in =~ s/\s+//sg;
        ($day, $open, $high, $low, $close, $vol, $dum) = split /;/, $in;
        last if ($day lt $dayBeg);
        next unless ($vol > 0);
        # check if the day is in the dates already inserted
        $newdata = 1;
        DAY:foreach $d (@date) {
            if ($d eq $day) {
                $newdata = 0;
                last DAY;
            }
        }
        if ($newdata) {
#            print "would insert $day: $open, $high, $low, $close, $vol\n";
            print "inserting $day from ARIVA... ";
            $dbh -> do(qq{INSERT into stockprices (symbol, date, day_open, day_high, day_low, day_close, volume) VALUES('$tick','$day',$open,$high,$low,$close,$vol)});
        }
    }

}